
//Chemical Reactions - Initialises all /datum/chemical_reaction into a list
// It is filtered into multiple lists within a list.
// For example:
// chemical_reaction_list["plasma"] is a list of all reactions relating to plasma
// Note that entries in the list are NOT duplicated. So if a reaction pertains to
// more than one chemical it will still only appear in only one of the sublists.
/proc/initialize_chemical_reactions()
	var/paths = typesof(/datum/chemical_reaction) - /datum/chemical_reaction
	GLOB.chemical_reactions_list = list()

	for(var/path in paths)
		var/datum/chemical_reaction/D = new path()
		for(var/id in D.required_reagents)
			if(!is_reagent_with_id_exist(id))
				error("recipe [D.type] created incorectly,\[required_reagents\] reagent with id \"[id]\" does not exist.")
		for(var/id in D.catalysts)
			if(!is_reagent_with_id_exist(id))
				error("recipe [D.type] created incorectly,\[catalysts\] reagent with id [id] does not exist.")
		for(var/id in D.inhibitors)
			if(!is_reagent_with_id_exist(id))
				error("recipe [D.type] created incorectly,\[inhibitors\] reagent with id [id] does not exist.")
		for(var/id in D.byproducts)
			if(!is_reagent_with_id_exist(id))
				error("recipe [D.type] created incorectly,\[byproducts\] reagent with id [id] does not exist.")
		if(D.required_reagents && D.required_reagents.len)
			if(D.result)
				if(!GLOB.chemical_reactions_list_by_result[D.result])
					GLOB.chemical_reactions_list_by_result[D.result] = list()
				GLOB.chemical_reactions_list_by_result[D.result] += D
			var/reagent_id = D.required_reagents[1]
			if(!GLOB.chemical_reactions_list[reagent_id])
				GLOB.chemical_reactions_list[reagent_id] = list()
			GLOB.chemical_reactions_list[reagent_id] += D

//helper that ensures the reaction rate holds after iterating
//Ex. REACTION_RATE(0.3) means that 30% of the reagents will react each chemistry tick (~2 seconds by default).
#define REACTION_RATE(rate) (1.0 - (1.0-rate)**(1.0/PROCESS_REACTION_ITER))

//helper to define reaction rate in terms of half-life
//Ex.
//HALF_LIFE(0) -> Reaction completes immediately (default chems)
//HALF_LIFE(1) -> Half of the reagents react immediately, the rest over the following ticks.
//HALF_LIFE(2) -> Half of the reagents are consumed after 2 chemistry ticks.
//HALF_LIFE(3) -> Half of the reagents are consumed after 3 chemistry ticks.
#define HALF_LIFE(ticks) (ticks? 1.0 - (0.5)**(1.0/(ticks*PROCESS_REACTION_ITER)) : 1.0)

/datum/chemical_reaction
	var/result = null
	var/list/required_reagents = list()
	var/list/catalysts = list()
	var/list/inhibitors = list()
	var/result_amount = 0
	var/list/byproducts= list()

	//how far the reaction proceeds each time it is processed. Used with either REACTION_RATE or HALF_LIFE macros.
	var/reaction_rate = HALF_LIFE(0)

	//if less than 1, the reaction will be inhibited if the ratio of products/reagents is too high.
	//0.5 = 50% yield -> reaction will only proceed halfway until products are removed.
	var/yield = 1.0

	// Reaction thermal requirements
	var/maximum_temperature = INFINITY
	var/minimum_temperature = 0
	var/thermal_product // Heat generated by the reaction

	var/rotation_required = FALSE

	// if true then chemical can be decomposed to initial reagents
	var/supports_decomposition_by_electrolysis = TRUE

	//If limits on reaction rate would leave less than this amount of any reagent (adjusted by the reaction ratios),
	//the reaction goes to completion. This is to prevent reactions from going on forever with tiny reagent amounts.
	var/min_reaction = 2

	var/mix_message = "The solution begins to bubble."
	var/reaction_sound = 'sound/effects/bubbles.ogg'

	var/list/require_containers = list() // This reaction will only occure in these containers(Or their subtypes).
	var/list/blacklist_containers = list(/obj/machinery/microwave) // This reaction will not occure in these containers(Or their subtypes).

	var/log_is_important = 0 // If this reaction should be considered important for logging. Important recipes message admins when mixed, non-important ones just log to file.

/datum/chemical_reaction/proc/can_happen(datum/reagents/holder)
	//check that all the required reagents are present
	if(!holder.has_all_reagents(required_reagents))
		return FALSE

	//check that all the required catalysts are present in the required amount
	if(!holder.has_all_reagents(catalysts))
		return FALSE

	//check that none of the inhibitors are present in the required amount
	if(holder.has_any_reagent(inhibitors))
		return FALSE

	if(require_containers.len && !is_type_in_list(holder.my_atom, require_containers))
		return FALSE

	if(blacklist_containers.len && is_type_in_list(holder.my_atom, blacklist_containers))
		return FALSE

	var/temperature = holder.chem_temp
	if(temperature < minimum_temperature || temperature > maximum_temperature)
		return FALSE

	if(rotation_required && !holder.rotating)
		return FALSE

	return TRUE

/datum/chemical_reaction/proc/calc_reaction_progress(var/datum/reagents/holder, var/reaction_limit)
	var/progress = reaction_limit * reaction_rate //simple exponential progression

	//calculate yield
	if(1-yield > 0.001) //if yield ratio is big enough just assume it goes to completion
		/*
			Determine the max amount of product by applying the yield condition:
			(max_product/result_amount) / reaction_limit == yield/(1-yield)

			We make use of the fact that:
			reaction_limit = (holder.get_reagent_amount(reactant) / required_reagents[reactant]) of the limiting reagent.
		*/
		var/yield_ratio = yield/(1-yield)
		var/max_product = yield_ratio * reaction_limit * result_amount //rearrange to obtain max_product
		var/yield_limit = max(0, max_product - holder.get_reagent_amount(result))/result_amount

		progress = min(progress, yield_limit) //apply yield limit

	//apply min reaction progress - wasn't sure if this should go before or after applying yield
	//I guess people can just have their miniscule reactions go to completion regardless of yield.
	for(var/reactant in required_reagents)
		var/remainder = holder.get_reagent_amount(reactant) - progress*required_reagents[reactant]
		if(remainder <= min_reaction*required_reagents[reactant])
			progress = reaction_limit
			break

	return progress

// This proc returns a list of all reagents it wants to use; if the holder has several reactions that use the same reagent, it will split the reagent evenly between them
/datum/chemical_reaction/proc/get_used_reagents()
	. = list()
	for(var/reagent in required_reagents)
		. += reagent

/datum/chemical_reaction/proc/process(datum/reagents/holder)
	//determine how far the reaction can proceed
	var/list/reaction_limits = list()
	for(var/reactant in required_reagents)
		reaction_limits += holder.get_reagent_amount(reactant) / required_reagents[reactant]

	//determine how far the reaction proceeds
	var/reaction_limit = min(reaction_limits)
	var/progress_limit = calc_reaction_progress(holder, reaction_limit)

	var/reaction_progress = min(reaction_limit, progress_limit) //no matter what, the reaction progress cannot exceed the stoichiometric limit.

	//need to obtain the new reagent's data before anything is altered
	var/data = send_data(holder, reaction_progress)

	//remove the reactants
	for(var/reactant in required_reagents)
		var/amt_used = required_reagents[reactant] * reaction_progress
		holder.remove_reagent(reactant, amt_used, safety = 1)

	//add the product
	var/amt_produced = result_amount * reaction_progress
	if(result)
		holder.add_reagent(result, amt_produced, data, safety = 1)

	on_reaction(holder, amt_produced)

	return reaction_progress

//called when a reaction processes
/datum/chemical_reaction/proc/on_reaction(var/datum/reagents/holder, var/created_volume)
	if(thermal_product)
		holder.chem_temp += thermal_product
	var/datum/reagents/to_splash = new()
	to_splash.maximum_volume = INFINITY
	//well i'll never test this cause there is no recipes with byproducts, so if YOU, yes you, the one who decided to add some, its up to you to fix this
	if(byproducts.len)
		for(var/i = 1 to created_volume/result_amount) // this to evenly fill holder
			for(var/id in byproducts)
				if(holder.get_free_space() > byproducts[id])
					holder.add_reagent(id, byproducts[id], safety = 1)
				else
					to_splash.add_reagent(id, byproducts[id], safety = 1)
	if(to_splash.total_volume)
		to_splash.handle_reactions()
		to_splash.splash(get_turf(holder.my_atom), to_splash.total_volume, 1, FALSE, to_splash.total_volume, to_splash.total_volume)
		qdel(to_splash)


//called after processing reactions, if they occurred
/datum/chemical_reaction/proc/post_reaction(var/datum/reagents/holder)
	var/atom/container = holder.my_atom
	if(mix_message && container && !ismob(container))
		var/turf/T = get_turf(container)
		var/list/seen = viewers(4, T)
		for(var/mob/M in seen)
			M.show_message(SPAN_NOTICE("\icon[container] [mix_message]"), 1)
		playsound(T, reaction_sound, 80, 1)

//obtains any special data that will be provided to the reaction products
//this is called just before reactants are removed.
/datum/chemical_reaction/proc/send_data(var/datum/reagents/holder, var/reaction_limit)
	return null

// UI data used by chemical catalog
/datum/chemical_reaction/ui_data()
	var/list/dat = list()
	if(required_reagents)
		dat["reagents"] = list()
		for(var/id in required_reagents)
			dat["reagents"] += list(list("type" = get_reagent_type_by_id(id), "reagent" = get_reagent_name_by_id(id), "parts" = "[required_reagents[id]] part\s"))
	if(catalysts)
		dat["catalyst"] = list()
		for(var/id in catalysts)
			dat["catalyst"] += list(list("type" = get_reagent_type_by_id(id), "reagent" = get_reagent_name_by_id(id), "units" = catalysts[id]))
	if(inhibitors)
		dat["inhibitors"] = list()
		for(var/id in inhibitors)
			dat["inhibitors"] += list(list("type" = get_reagent_type_by_id(id), "reagent" = get_reagent_name_by_id(id), "units" = inhibitors[id]))
	if(byproducts)
		dat["byproducts"] = list()
		for(var/id in byproducts)
			dat["byproducts"] += list(list("type" = get_reagent_type_by_id(id), "reagent" = get_reagent_name_by_id(id), "units" = byproducts[id]))

	dat["minimum_temperature"] = minimum_temperature
	if(maximum_temperature != INFINITY)
		dat["maximum_temperature"] = maximum_temperature

	dat["result_amount"] = "[result_amount] part\s"
	return dat
