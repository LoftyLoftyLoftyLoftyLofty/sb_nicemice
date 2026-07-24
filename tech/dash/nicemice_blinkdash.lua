oldUpdate = update

function update(args)
	oldUpdate(args)
	
	if world.entitySpecies(entity.id()) == "nicemice" then
		if animator.animationState("blinking") == "in" then
			animator.setAnimationState("blinking", "off")
			animator.setAnimationState("nicemice_blinking", "in")
		elseif animator.animationState("blinking") == "out" then
			animator.setAnimationState("blinking", "off")
			animator.setAnimationState("nicemice_blinking", "out")
		end
	end
end