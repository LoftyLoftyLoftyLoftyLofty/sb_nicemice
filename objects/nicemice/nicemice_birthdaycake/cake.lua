function update(dt)
	for i = 1, 5 do
	  if math.random() < .0175 then
	    animator.burstParticleEmitter("torch" .. i)
	  end
	end
end