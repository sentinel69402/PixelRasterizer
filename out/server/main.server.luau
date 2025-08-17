-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Lighting = _services.Lighting
local RunService = _services.RunService
local Workspace = _services.Workspace
-- constants
local batchSize = 200
local FORCE_UPDATE_INT = 15
local allTrackedParts = {}
-- shadow constants
local SHADOW_COLOR = Color3.fromRGB(50, 50, 100)
local LIGHT_COLOR = Color3.fromRGB(255, 255, 200)
local SHADOW_TRANSPARENCY = 0.01
local LIGHT_TRANSPARENCY = 0
-- mutables
local index = 0
local globalFrameCount = 0
local refresh_timer = 0
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
--[[
	*
	 * Get the primary light direction (from sun/directional light)
	 * @returns {Vector3}
	 
]]
local function getLightDirection()
	local sunDirection = Lighting:GetSunDirection()
	if globalFrameCount % 60 == 0 then
		print(`Sun direction: {sunDirection.X},{sunDirection.Y},{sunDirection.Z}`)
	end
	return sunDirection.Unit
end
--[[
	*
	 * Cast a shadow ray to detect if a point is in shadow
	 * @param {Vector3} position  The position to check for shadows
	 * @param {Vector3} lightDirection Direction towards light source 
	 * @param {BasePart} sourcePart The part we're casting from
	 * @param {number} maxDistance Maximum distance to cast the shadow ray
	 * @returns {boolean} True if the point is in shadow
	 
]]
local function isInShadow(position, lightDirection, sourcePart, maxDistance)
	if maxDistance == nil then
		maxDistance = 1000
	end
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local rayModel = sourcePart.Parent
	local filterList = { sourcePart }
	if rayModel then
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
	 * 
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
			task.wait()
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
					part.Color = Color3.fromRGB(255, 0, 0)
					part.Parent = model
					local _arg0 = {
						part = part,
						lastPos = part.Position,
						lastRot = part.Orientation,
						lastLook = part.CFrame.LookVector,
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
	 * 
	 * @param {TrackedPart} data the data of the part
	 * @param {number} currentFrame the current frame
	 * @returns {void}
	 
]]
local function updatePart(data, currentFrame)
	local part = data.part
	local pos = part.Position
	local rot = part.Orientation
	local look = part.CFrame.LookVector
	local forceUpdate = currentFrame % FORCE_UPDATE_INT == 0
	local moved = not fuzzyEqual(pos, data.lastPos) or not fuzzyEqual(rot, data.lastRot) or not fuzzyEqual(look, data.lastLook) or forceUpdate
	data.lastPos = pos
	data.lastRot = rot
	data.lastLook = look
	if moved then
		local rayResult = Workspace:Raycast(pos, look * 100)
		if rayResult then
			local hitPoint = rayResult.Position
			local surfaceNormal = rayResult.Normal
			local lightDirection = getLightDirection()
			local _arg0 = surfaceNormal * 0.1
			local testPosition = hitPoint + _arg0
			local inShadow = isInShadow(testPosition, lightDirection, part)
			if inShadow then
				local originalColor = rayResult.Instance.Color
				local blendAmount = 0.6
				local r = originalColor.R * (1 - blendAmount) + SHADOW_COLOR.R * blendAmount
				local g = originalColor.G * (1 - blendAmount) + SHADOW_COLOR.G * blendAmount
				local b = originalColor.B * (1 - blendAmount) + SHADOW_COLOR.B * blendAmount
				part.Color = Color3.new(r, g, b)
				part.Transparency = SHADOW_TRANSPARENCY
				part.Material = rayResult.Instance.Material
			else
				local originalColor = rayResult.Instance.Color
				local r = math.min(1, originalColor.R * 0.7 + LIGHT_COLOR.R * 0.3)
				local g = math.min(1, originalColor.G * 0.7 + LIGHT_COLOR.G * 0.3)
				local b = math.min(1, originalColor.B * 0.7 + LIGHT_COLOR.B * 0.3)
				part.Color = Color3.fromRGB(r * 255, g * 255, b * 255)
				part.Transparency = LIGHT_TRANSPARENCY
				part.Material = rayResult.Instance.Material
			end
		else
			part.Transparency = 1
		end
	end
end
local _arg0 = rayModel(70, 35, CFrame.new(0, 0, 0))
table.insert(allTrackedParts, _arg0)
RunService.Heartbeat:Connect(function(dT)
	refresh_timer += dT
	if refresh_timer < 1 / 20 then
		return nil
	end
	refresh_timer = 0
	globalFrameCount += 1
	local isForceUpdateFrame = globalFrameCount % FORCE_UPDATE_INT == 0
	if isForceUpdateFrame then
		local trackedParts = allTrackedParts[1]
		for i = 0, #trackedParts - 1 do
			updatePart(trackedParts[i + 1], globalFrameCount)
		end
	else
		for i = 0, batchSize - 1 do
			local trackedParts = allTrackedParts[1]
			local data = trackedParts[index + 1]
			updatePart(data, globalFrameCount)
			index = (index + 1) % #trackedParts
		end
	end
end)
