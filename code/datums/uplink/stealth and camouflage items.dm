/*******************************
* Stealth and Camouflage Items *
*******************************/
/datum/uplink_item/item/stealth_items
	category = /datum/uplink_category/stealth_items

/datum/uplink_item/item/stealth_items/syndigaloshes
	name = "No-Slip sole"
	item_cost = 1
	path = /obj/item/noslipmodule

/datum/uplink_item/item/stealth_items/spy
	name = "Bug Kit"
	item_cost = 2
	path = /obj/item/storage/box/syndie_kit/spy

/datum/uplink_item/item/stealth_items/id
	name = "Agent ID card"
	item_cost = 3
	path = /obj/item/card/id/syndicate
//	antag_roles = list(ROLE_TRAITOR,ROLE_MARSHAL,ROLE_INQUISITOR,ROLE_MERCENARY,ROLE_CARRION)

/datum/uplink_item/item/stealth_items/chameleon_kit
	name = "Chameleon Kit"
	item_cost = 5
	path = /obj/item/storage/box/syndie_kit/chameleon

/datum/uplink_item/item/stealth_items/voice
	name = "Voice Changer"
	item_cost = 5
	path = /obj/item/clothing/mask/gas/voice

/datum/uplink_item/item/stealth_items/chameleon_projector
	name = "Chameleon-Projector"
	item_cost = 8
	path = /obj/item/device/chameleon

/datum/uplink_item/item/stealth_items/dna_trigger
	name = "SI \"DNA lock\" trigger"
	item_cost = 2 //low do to like being really really unuseful
	path = /obj/item/weapon/gun_upgrade/trigger/dnalock

/datum/uplink_item/item/stealth_items/tool_dampener
	name = "Tool Upgrade: Aural Dampener"
	item_cost = 1
	path = /obj/item/tool_upgrade/augment/dampener