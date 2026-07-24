oldUpdate = update

function update(args)
	oldUpdate(args)
	
	if world.entitySpecies(entity.id()) == "nicemice" then
		if animator.animationState("dashing") == "on" then
			animator.setParticleEmitterActive("dashParticles", false)
			animator.setParticleEmitterActive("nicemice_dashParticles", true)
		else
			animator.setParticleEmitterActive("nicemice_dashParticles", false)
		end
	end
end