-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local RunService = _services.RunService
local Workspace = _services.Workspace
-- constants
local batchSize = 200
local FORCE_UPDATE_INT = 15
local allTrackedParts = {}
-- mutables
local index = 0
local globalFrameCount = 0
local refresh_timer = 0
--[[
	* 
	 *  @param {Vector3} a - 1st vector3
	 *  @param {Vector3} b - 2nd vector3
	 *  @param {number} [epsilon = 0.001] - optional param for tolerance threshold
	 *  @returns {boolean}
	 
]]
local function fuzzyEqual(a, b, epsilon)
	if epsilon == nil then
		epsilon = 0.001
	end
	return math.abs(a.X - b.X) < epsilon and math.abs(a.Y - b.Y) < epsilon and math.abs(a.Z - b.Z) < epsilon
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
			part.Transparency = 0
			part.Color = rayResult.Instance.Color
		else
			part.Transparency = 1
		end
	end
end
local _arg0 = rayModel(60, 20, CFrame.new(0, 0, 0))
table.insert(allTrackedParts, _arg0)
RunService.Heartbeat:Connect(function(dT)
	refresh_timer += dT
	if refresh_timer < 1 / 15 then
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
