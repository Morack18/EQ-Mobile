class_name MerchantPolicy
extends RefCounted

## Domain authorization policy. Presentation can choose how to display a denial,
## but it does not decide whether the interaction is allowed.

static func can_browse(standing: String) -> bool:
	return standing in [
		"Ally",
		"Warmly",
		"Kindly",
		"Amiably",
		"Indifferently",
		"Apprehensively",
	]