// Every cycle, the pump uses the air in air_in to try and make air_out the perfect pressure.
//
// node1, air1, network1 correspond to input
// node2, air2, network2 correspond to output
//
// Thus, the two variables affect pump operation are set in New():
//   air1.volume
//     This is the volume of gas available to the pump that may be transfered to the output
//   air2.volume
//     Higher quantities of this cause more air to be perfected later
//     but overall network volume is also increased as this increases...

/obj/machinery/atmospherics/components/binary/volume_pump
	icon_state = "volpump_map-2"
	name = "volumetric gas pump"
	desc = "A pump that moves gas by volume."

	can_unwrench = TRUE
	shift_underlay_only = FALSE

	var/transfer_rate = MAX_TRANSFER_RATE

	var/frequency = 0
	var/id = null
	var/datum/radio_frequency/radio_connection

	construction_type = /obj/item/pipe/directional
	pipe_state = "volumepump"

/obj/machinery/atmospherics/components/binary/volume_pump/examine(mob/user)
	. = ..()
	. += "<span class='notice'>You can hold <b>Ctrl</b> and click on it to toggle it on and off.</span>"
	. += "<span class='notice'>You can hold <b>Alt</b> and click on it to maximize its pressure.</span>"

/obj/machinery/atmospherics/components/binary/volume_pump/CtrlClick(mob/user)
	var/area/A = get_area(src)
	var/turf/T = get_turf(src)
	if(user.canUseTopic(src, BE_CLOSE, FALSE,))
		on = !on
		update_icon()
		investigate_log("Volume Pump, [src.name], turned on by [key_name(usr)] at [x], [y], [z], [A]", INVESTIGATE_ATMOS)
		message_admins("Volume Pump, [src.name], turned [on ? "on" : "off"] by [ADMIN_LOOKUPFLW(usr)] at [ADMIN_COORDJMP(T)], [A]")
		return ..()

/obj/machinery/atmospherics/components/binary/volume_pump/Destroy()
	SSradio.remove_object(src,frequency)
	return ..()

/obj/machinery/atmospherics/components/binary/volume_pump/update_icon_nopipes()
	icon_state = on && is_operational() ? "volpump_on" : "volpump_off"

/obj/machinery/atmospherics/components/binary/volume_pump/process_atmos()
//	..()
	if(!on || !is_operational())
		return

	var/datum/gas_mixture/air1 = airs[1]
	var/datum/gas_mixture/air2 = airs[2]

// Pump mechanism just won't do anything if the pressure is too high/too low

	var/input_starting_pressure = air1.return_pressure()
	var/output_starting_pressure = air2.return_pressure()

	if((input_starting_pressure < 0.01) || (output_starting_pressure > 9000))
		return

	var/transfer_ratio = transfer_rate/air1.return_volume()

	var/datum/gas_mixture/removed = air1.remove_ratio(transfer_ratio)

	air2.merge(removed)

	update_parents()

/obj/machinery/atmospherics/components/binary/volume_pump/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	if(frequency)
		radio_connection = SSradio.add_object(src, frequency)

/obj/machinery/atmospherics/components/binary/volume_pump/proc/broadcast_status()
	if(!radio_connection)
		return

	var/datum/signal/signal = new(list(
		"tag" = id,
		"device" = "APV",
		"power" = on,
		"transfer_rate" = transfer_rate,
		"sigtype" = "status"
	))
	radio_connection.post_signal(src, signal)

/obj/machinery/atmospherics/components/binary/volume_pump/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AtmosPump", name)
		ui.open()

/obj/machinery/atmospherics/components/binary/volume_pump/ui_data()
	var/data = list()
	data["on"] = on
	data["rate"] = round(transfer_rate)
	data["max_rate"] = round(MAX_TRANSFER_RATE)
	return data

/obj/machinery/atmospherics/components/binary/volume_pump/atmosinit()
	..()

	set_frequency(frequency)

/obj/machinery/atmospherics/components/binary/volume_pump/ui_act(action, params)
	if(..())
		return
	var/turf/T = get_turf(src)
	var/area/A = get_area(src)
	switch(action)
		if("power")
			on = !on
			message_admins("Pump, [src.name], turned [on ? "on" : "off"] by [ADMIN_LOOKUPFLW(usr)] at [ADMIN_COORDJMP(T)], [A]")
			investigate_log("was turned [on ? "on" : "off"] by [key_name(usr)]", INVESTIGATE_ATMOS)
			. = TRUE
		if("rate")
			var/rate = params["rate"]
			if(rate == "max")
				rate = MAX_TRANSFER_RATE
				. = TRUE
			else if(rate == "input")
				rate = input("New transfer rate (0-[MAX_TRANSFER_RATE] L/s):", name, transfer_rate) as num|null
				if(!isnull(rate) && !..())
					. = TRUE
			else if(text2num(rate) != null)
				rate = text2num(rate)
				. = TRUE
			if(.)
				transfer_rate = clamp(rate, 0, MAX_TRANSFER_RATE)
				investigate_log("was set to [transfer_rate] L/s by [key_name(usr)]", INVESTIGATE_ATMOS)
	update_icon()

/obj/machinery/atmospherics/components/binary/volume_pump/receive_signal(datum/signal/signal)
	if(!signal.data["tag"] || (signal.data["tag"] != id) || (signal.data["sigtype"]!="command"))
		return

	var/old_on = on //for logging

	if("power" in signal.data)
		on = text2num(signal.data["power"])

	if("power_toggle" in signal.data)
		on = !on

	if("set_transfer_rate" in signal.data)
		var/datum/gas_mixture/air1 = airs[1]
		transfer_rate = clamp(text2num(signal.data["set_transfer_rate"]),0,air1.return_volume())

	if(on != old_on)
		investigate_log("was turned [on ? "on" : "off"] by a remote signal", INVESTIGATE_ATMOS)

	if("status" in signal.data)
		broadcast_status()
		return //do not update_icon

	broadcast_status()
	update_icon()

/obj/machinery/atmospherics/components/binary/volume_pump/power_change()
	..()
	update_icon()

/obj/machinery/atmospherics/components/binary/volume_pump/can_unwrench(mob/user)
	. = ..()
	var/area/A = get_area(src)
	if(. && on && is_operational())
		to_chat(user, "<span class='warning'>You cannot unwrench [src], turn it off first!</span>")
		return FALSE
	else
		investigate_log("Pump, [src.name], was unwrenched by [key_name(usr)] at [x], [y], [z], [A]", INVESTIGATE_ATMOS)
		message_admins("Pump, [src.name], was unwrenched by [ADMIN_LOOKUPFLW(user)] at [A]")
		return TRUE

// Mapping

/obj/machinery/atmospherics/components/binary/volume_pump/layer1
	piping_layer = 1
	icon_state = "volpump_map-1"

/obj/machinery/atmospherics/components/binary/volume_pump/layer3
	piping_layer = 3
	icon_state = "volpump_map-3"

/obj/machinery/atmospherics/components/binary/volume_pump/on
	on = TRUE
	icon_state = "volpump_on_map"

/obj/machinery/atmospherics/components/binary/volume_pump/on/layer1
	piping_layer = 1
	icon_state = "volpump_map-1"

/obj/machinery/atmospherics/components/binary/volume_pump/on/layer3
	piping_layer = 3
	icon_state = "volpump_map-3"
