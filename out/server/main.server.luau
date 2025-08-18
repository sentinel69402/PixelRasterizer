-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Lighting = _services.Lighting
local RunService = _services.RunService
local Workspace = _services.Workspace
-- constants
local batchSize = 200
local FORCE_UPDATE_INT = 10
local allTrackedParts = {}
local raycastParams = RaycastParams.new()
local filterList = {}
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
local skybox = true
local skyboxColor = Color3.fromRGB(51, 168, 247)
-- shadow constants
local SHADOW_COLOR = Color3.fromRGB(50, 50, 100)
local LIGHT_COLOR = Color3.fromRGB(255, 255, 200)
local SHADOW_TRANSPARENCY = 0.01
local LIGHT_TRANSPARENCY = 0
-- mutables
local index = 0
local globalFrameCount = 0
local refresh_timer = 0
local shadowLimiter = 0
--[[
	* 
	 *  @param {Vector3} a - 1st vector3
	 *  @param {Vector3} b - 2nd vector3
	 *  @param {number} [epsilon = 0.001] - optional param for tolerance threshold
	 *  @returns {boolean} true/false
	 
]]
local function fuzzyEqual(a, b, epsilon)
	if epsilon == nil then
		epsilon = 0.001
	end
	return math.abs(a.X - b.X) < epsilon and math.abs(a.Y - b.Y) < epsilon and math.abs(a.Z - b.Z) < epsilon
end
local function fuzzyColorEq(a, b, epsilon)
	if epsilon == nil then
		epsilon = 0.01
	end
	return math.abs(a.R - b.R) < epsilon and math.abs(a.G - b.G) < epsilon and math.abs(a.B - b.B) < epsilon
end
--[[
	*
	 * Get the primary light direction (from sun/directional light)
	 * @returns {Vector3}
	 
]]
local function getLightDirection()
	local sunDirection = Lighting:GetSunDirection()
	return sunDirection.Unit
end
--[[
	*
	 * Cast a shadow ray to detect if a point is in shadow
	 * @param {Vector3} position  The position to check for shadows
	 * @param {Vector3} lightDirection Direction towards light source 
	 * @param {BasePart} sourcePart The part we're casting from
	 * @param {number} maxDistance Maximum distance to cast the shadow ray
	 * @param {number} maxShadowRays Maximum shadow rays allowed this frame
	 * @returns {boolean} True if the point is in shadow
	 
]]
local function isInShadow(position, lightDirection, sourcePart, maxDistance, maxShadowRays)
	if maxDistance == nil then
		maxDistance = 300
	end
	if shadowLimiter >= maxShadowRays then
		return false
	end
	shadowLimiter += 1
	local rayModel = sourcePart.Parent
	table.clear(filterList)
	if sourcePart and rayModel then
		local _sourcePart = sourcePart
		table.insert(filterList, _sourcePart)
		table.insert(filterList, rayModel)
	end
	raycastParams.FilterDescendantsInstances = filterList
	local _position = position
	local _arg0 = lightDirection.Unit * 0.1
	local offsetPos = _position + _arg0
	local _lightDirection = lightDirection
	local _maxDistance = maxDistance
	local shadowRay = Workspace:Raycast(offsetPos, _lightDirection * _maxDistance, raycastParams)
	return shadowRay ~= nil
end
--[[
	*
	 * Create a grid of raycast parts for lighting analysis
	 * @param {number} x_parts nr of parts on the x-axis 
	 * @param {number} y_parts nr of parts on the y-axis
	 * @param {CFrame} position optional param for the position of the model
	 * @returns {TrackedPart[]}
	 
]]
local function rayModel(x_parts, y_parts, position)
	local model = Instance.new("Model")
	model.Name = "RayModel"
	model.Parent = Workspace
	local _condition = position
	if _condition then
		local _position = position
		_condition = typeof(_position) == "CFrame"
	end
	if _condition then
		model:PivotTo(position)
	else
		local _condition_1 = position
		if _condition_1 then
			local _position = position
			_condition_1 = typeof(_position) ~= "CFrame"
		end
		if _condition_1 then
			error("position must be a CFrame")
		end
	end
	local tracked = {}
	do
		local x = 0
		local _shouldIncrement = false
		while true do
			if _shouldIncrement then
				x += 1
			else
				_shouldIncrement = true
			end
			if not (x < x_parts) then
				break
			end
			do
				local y = 0
				local _shouldIncrement_1 = false
				while true do
					if _shouldIncrement_1 then
						y += 1
					else
						_shouldIncrement_1 = true
					end
					if not (y < y_parts) then
						break
					end
					local part = Instance.new("Part")
					part.Size = Vector3.new(1, 1, 1)
					part.Position = Vector3.new(x, y, 0)
					part.Anchored = true
					part.CastShadow = false
					part.CanCollide = false
					part.Color = Color3.fromRGB(255, 0, 0)
					part.Parent = model
					local _arg0 = {
						part = part,
						lastHitInstance = nil,
						lastHitPosition = nil,
						lastHitMaterial = nil,
						lastLightDirection = nil,
					}
					table.insert(tracked, _arg0)
				end
			end
		end
	end
	return tracked
end
--[[
	*
	 * Update a single tracked part with lighting information
	 * @param {TrackedPart} data the data of the part
	 * @param {number} currentFrame the current frame
	 * @param {Vector3} lightDirection current light direction
	 * @param {number} maxShadowRays maximum shadow rays for this update cycle
	 * @returns {void}
	 
]]
local function updatePart(data, currentFrame, lightDirection, maxShadowRays)
	local part = data.part
	local rayResult = Workspace:Raycast(part.Position, part.CFrame.LookVector * 100)
	local forceUpdate = currentFrame % FORCE_UPDATE_INT == 0
	local _hitInstance = rayResult
	if _hitInstance ~= nil then
		_hitInstance = _hitInstance.Instance
	end
	local hitInstance = _hitInstance
	local _hitPosition = rayResult
	if _hitPosition ~= nil then
		_hitPosition = _hitPosition.Position
	end
	local hitPosition = _hitPosition
	local _hitMaterial = rayResult
	if _hitMaterial ~= nil then
		_hitMaterial = _hitMaterial.Instance
		if _hitMaterial ~= nil then
			_hitMaterial = _hitMaterial.Material
		end
	end
	local hitMaterial = _hitMaterial
	local sceneChanged = hitInstance ~= data.lastHitInstance or (hitPosition and data.lastHitPosition and not fuzzyEqual(hitPosition, data.lastHitPosition)) or (hitPosition and not data.lastHitPosition) or (not hitPosition and data.lastHitPosition) or hitMaterial ~= data.lastHitMaterial
	local lightChanged = not data.lastLightDirection or not fuzzyEqual(lightDirection, data.lastLightDirection)
	data.lastHitInstance = hitInstance
	data.lastHitPosition = hitPosition
	data.lastHitMaterial = hitMaterial
	data.lastLightDirection = lightDirection
	if sceneChanged or lightChanged or forceUpdate then
		if rayResult then
			local hitPoint = rayResult.Position
			local surfaceNormal = rayResult.Normal
			local _arg0 = surfaceNormal * 0.1
			local testPosition = hitPoint + _arg0
			local inShadow = isInShadow(testPosition, lightDirection, part, 300, maxShadowRays)
			if inShadow then
				local originalColor = rayResult.Instance.Color
				local blendAmount = 0.6
				local r = originalColor.R * (1 - blendAmount) + SHADOW_COLOR.R * blendAmount
				local g = originalColor.G * (1 - blendAmount) + SHADOW_COLOR.G * blendAmount
				local b = originalColor.B * (1 - blendAmount) + SHADOW_COLOR.B * blendAmount
				local newColor = Color3.new(r, g, b)
				if not fuzzyColorEq(part.Color, newColor) then
					part.Color = newColor
				end
				if part.Transparency ~= SHADOW_TRANSPARENCY then
					part.Transparency = SHADOW_TRANSPARENCY
				end
				if part.Material ~= rayResult.Instance.Material then
					part.Material = rayResult.Instance.Material
				end
			else
				local originalColor = rayResult.Instance.Color
				local r = math.min(1, originalColor.R * 0.3 + LIGHT_COLOR.R * 0.4)
				local g = math.min(1, originalColor.G * 0.3 + LIGHT_COLOR.G * 0.4)
				local b = math.min(1, originalColor.B * 0.3 + LIGHT_COLOR.B * 0.4)
				local newColor = Color3.fromRGB(r * 255, g * 255, b * 255)
				if not fuzzyColorEq(part.Color, newColor) then
					part.Color = newColor
				end
				if part.Transparency ~= LIGHT_TRANSPARENCY then
					part.Transparency = LIGHT_TRANSPARENCY
				end
				if part.Material ~= rayResult.Instance.Material then
					part.Material = rayResult.Instance.Material
				end
			end
		else
			if skybox then
				part.Transparency = 0
				part.Material = Enum.Material.SmoothPlastic
				local r = skyboxColor.R * (1 - 0.6) + LIGHT_COLOR.R * 0.6
				local g = skyboxColor.G * (1 - 0.6) + LIGHT_COLOR.G * 0.6
				local b = skyboxColor.B * (1 - 0.6) + LIGHT_COLOR.B * 0.6
				part.Color = Color3.fromRGB(r * 255, g * 255, b * 255)
			else
				part.Transparency = 1
			end
		end
	end
end
local _arg0 = rayModel(70, 30, CFrame.new(0, 0, 0))
table.insert(allTrackedParts, _arg0)
RunService.Heartbeat:Connect(function(dT)
	refresh_timer += dT
	if refresh_timer < 1 / 20 then
		return nil
	end
	refresh_timer = 0
	shadowLimiter = 0
	globalFrameCount += 1
	local lightDirection = getLightDirection()
	local isForceUpdateFrame = globalFrameCount % FORCE_UPDATE_INT == 0
	if isForceUpdateFrame then
		local trackedParts = allTrackedParts[1]
		local maxForceUpdates = 500
		local shadowLimit = 500
		do
			local i = 0
			local _shouldIncrement = false
			while true do
				if _shouldIncrement then
					i += 1
				else
					_shouldIncrement = true
				end
				if not (i < math.min(#trackedParts, maxForceUpdates)) then
					break
				end
				updatePart(trackedParts[i + 1], globalFrameCount, lightDirection, shadowLimit)
			end
		end
	else
		local shadowLimit = 200
		for i = 0, batchSize - 1 do
			local trackedParts = allTrackedParts[1]
			local data = trackedParts[index + 1]
			updatePart(data, globalFrameCount, lightDirection, shadowLimit)
			index = (index + 1) % #trackedParts
		end
	end
end)
