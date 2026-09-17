extends SceneTree

func _init() -> void:
	EqWorldSpace.run_contract_tests()
	print("PASS: EqWorldSpace implementation contract.")
	quit()
