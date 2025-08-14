-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local RunService = _services.RunService
local Workspace = _services.Workspace
local function vectorsEqual(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
local function fuzzyEqual(a, b, epsilon)
	if epsilon == nil then
		epsilon = 0.001
	end
	return math.abs(a.X - b.X) < epsilon and math.abs(a.Y - b.Y) < epsilon and math.abs(a.Z - b.Z) < epsilon
end
local function rayModel(x_parts, y_parts)
	local model = Instance.new("Model")
	model.Name = "RayModel"
	model.Parent = Workspace
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
local trackedParts = rayModel(60, 20)
local batchSize = 200
local index = 0
RunService.Stepped:Connect(function()
	for i = 0, batchSize - 1 do
		local data = trackedParts[index + 1]
		local part = data.part
		local pos = part.Position
		local rot = part.Orientation
		local look = part.CFrame.LookVector
		local moved = not fuzzyEqual(pos, data.lastPos) or not fuzzyEqual(rot, data.lastRot) or not fuzzyEqual(look, data.lastLook)
		data.lastPos = pos
		data.lastRot = rot
		data.lastLook = look
		if moved or true then
			local rayResult = Workspace:Raycast(pos, look * 100)
			if rayResult then
				part.Transparency = 0
				part.Color = rayResult.Instance.Color
			else
				part.Transparency = 1
			end
		end
		index = (index + 1) % #trackedParts
	end
end)
