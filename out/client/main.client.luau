-- Compiled with roblox-ts v3.0.0
local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
local _services = TS.import(script, game:GetService("ReplicatedStorage"), "rbxts_include", "node_modules", "@rbxts", "services")
local Lighting = _services.Lighting
local RunService = _services.RunService
local Workspace = _services.Workspace
--[[
	*
	 * Represents a pixel used for lighting analysis in the world.
	 * @property {Vector3} worldPosition - The world position corresponding to the pixel.
	 * @property {Vector3} rayDirection - The direction to cast rays for this pixel.
	 * @property {Instance | undefined} lastHitInstance - Last instance hit by raycast.
	 * @property {Vector3 | undefined} lastHitPosition - Last hit position from raycast.
	 * @property {Enum.Material | undefined} lastHitMaterial - Last material hit.
	 * @property {Vector3 | undefined} lastLightDirection - Last used light direction.
	 
]]
-- Constants for image size and performance tuning
local IMAGE_WIDTH = 70
local IMAGE_HEIGHT = 60
local TOTAL_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT
local FORCE_UPDATE_INT = 10
local BATCH_SIZE = 200
-- Create EditableImage
local AssetService = game:GetService("AssetService")
local editableImage = AssetService:CreateEditableImage({
	Size = Vector2.new(IMAGE_WIDTH, IMAGE_HEIGHT),
})
-- Image Label to display the EditableImage
local imageLabel = Instance.new("ImageLabel")
imageLabel.Size = UDim2.new(1, 0, 1, 0)
imageLabel.ImageContent = Content.fromObject(editableImage)
local ratioConstraint = Instance.new("UIAspectRatioConstraint")
ratioConstraint.Parent = imageLabel
ratioConstraint.AspectRatio = 1.65
local rendererPart = Instance.new("Part")
rendererPart.Name = "Renderer"
rendererPart.Anchored = true
local _cFrame = CFrame.new(Vector3.new(10, 3, 0))
local _arg0 = CFrame.Angles(0, math.rad(180), 0)
rendererPart.CFrame = _cFrame * _arg0
rendererPart.Size = Vector3.new(10, 10, 2)
rendererPart.Parent = Workspace
-- SurfaceGUI to hold the Image Label
local SurfaceGUI = Instance.new("SurfaceGui")
SurfaceGUI.CanvasSize = Vector2.new(IMAGE_WIDTH, IMAGE_HEIGHT)
SurfaceGUI.Parent = rendererPart
imageLabel.Parent = SurfaceGUI
-- Storage for pixel data and pixel color buffer
local pixelData = {}
local pixelBuffer = buffer.create(TOTAL_PIXELS * 4)
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
-- Predefined colors used for shadows, light, and skybox
local SHADOW_COLOR = {
	R = 50,
	G = 50,
	B = 100,
}
local LIGHT_COLOR = {
	R = 255,
	G = 255,
	B = 200,
}
local SKYBOX_COLOR = {
	R = 51,
	G = 168,
	B = 247,
}
-- State tracking variables
local pixelIndex = 0
local globalFrameCount = 0
local refresh_timer = 0
local shadowLimiter = 0
local didUpdateFrame = false
local lastFrameLightDir = nil
--[[
	*
	 * Initializes pixel data array with world positions and ray directions.
	 * @param {Vector3} centerPosition - The central world position for the pixel grid.
	 * @param {number} scale - Distance between adjacent pixels in world units.
	 
]]
local function initializePixelData(centerPosition, scale)
	if scale == nil then
		scale = 1
	end
	table.clear(pixelData)
	for y = 0, IMAGE_HEIGHT - 1 do
		for x = 0, IMAGE_WIDTH - 1 do
			local worldX = centerPosition.X - (x - IMAGE_WIDTH / 2) * scale
			local worldY = centerPosition.Y - (y - IMAGE_HEIGHT / 2) * scale
			local worldZ = centerPosition.Z
			local _arg0_1 = {
				worldPosition = Vector3.new(worldX, worldY, worldZ),
				rayDirection = Vector3.new(0, 0, 1),
				lastHitInstance = nil,
				lastHitPosition = nil,
				lastHitMaterial = nil,
				lastLightDirection = nil,
			}
			table.insert(pixelData, _arg0_1)
		end
	end
	local gridPart = Instance.new("Part")
	gridPart.Name = "RayOriginPlane"
	gridPart.Anchored = true
	gridPart.CanCollide = false
	gridPart.Transparency = 0.9
	gridPart.Material = Enum.Material.SmoothPlastic
	gridPart.Color = Color3.fromRGB(40, 40, 40)
	gridPart.Size = Vector3.new(IMAGE_WIDTH * scale, IMAGE_HEIGHT * scale, 0.05)
	local _cFrame_1 = CFrame.new(centerPosition)
	local _cFrame_2 = CFrame.new(0, 0, -0.025)
	gridPart.CFrame = _cFrame_1 * _cFrame_2
	gridPart.Parent = Workspace
end
--[[
	* 
	 * @deprecated - isn't used
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
	 * @deprecated - isn't used
	 * Converts 2D pixel coordinates to a linear index in the pixel buffer.
	 * Y coordinate is flipped to match image orientation.
	 * @param {number} x - The x coordinate of the pixel.
	 * @param {number} y - The y coordinate of the pixel.
	 * @returns {number} The linear pixel index.
	 
]]
local function worldToPixel(x, y)
	local flippedY = IMAGE_HEIGHT - 1 - y
	return flippedY * IMAGE_WIDTH + x
end
--[[
	*
	 * Writes RGBA color values into the pixel buffer at the specified pixel index.
	 * @param {number} pixelIndex - Index of the pixel to update.
	 * @param {number} r - Red channel value (0-255).
	 * @param {number} g - Green channel value (0-255).
	 * @param {number} b - Blue channel value (0-255).
	 * @param {number} [a=255] - Alpha channel value (default 255, fully opaque).
	 
]]
local function setPixelColor(pixelIndex, r, g, b, a)
	if a == nil then
		a = 255
	end
	local offset = pixelIndex * 4
	buffer.writeu8(pixelBuffer, offset, math.floor(r))
	buffer.writeu8(pixelBuffer, offset + 1, math.floor(g))
	buffer.writeu8(pixelBuffer, offset + 2, math.floor(b))
	buffer.writeu8(pixelBuffer, offset + 3, math.floor(a))
end
--[[
	*
	 * Retrieves the primary sunlight direction in the game world.
	 * @returns {Vector3} Unit vector representing sun direction.
	 
]]
local function getLightDirection()
	return Lighting:GetSunDirection().Unit
end
--[[
	*
	 * Casts a shadow ray from a given position towards the light direction to check for shadows.
	 * Limits the number of shadow rays per frame to control performance.
	 * @param {Vector3} position - World position to start the shadow ray.
	 * @param {Vector3} lightDirection - Direction of the light (unit vector).
	 * @param {number} [maxDistance=300] - Maximum raycast distance.
	 * @param {number} maxShadowRays - Maximum allowed shadow rays per frame.
	 * @returns {boolean} True if the position is in shadow, false otherwise.
	 
]]
local function isInShadow(position, lightDirection, maxDistance, maxShadowRays)
	if maxDistance == nil then
		maxDistance = 300
	end
	if shadowLimiter >= maxShadowRays then
		return false
	end
	shadowLimiter += 1
	local _position = position
	local _arg0_1 = lightDirection.Unit * 0.1
	local offsetPos = _position + _arg0_1
	local _lightDirection = lightDirection
	local _maxDistance = maxDistance
	local shadowRay = Workspace:Raycast(offsetPos, _lightDirection * _maxDistance, raycastParams)
	return shadowRay ~= nil
end
--[[
	*
	 * Updates the lighting data for a single pixel by raycasting and color blending.
	 * Applies shadow and light blending depending on occlusion.
	 * Caches last hit data to optimize updates.
	 * @param {number} pixelIdx - Index of the pixel in the pixelData array.
	 * @param {number} currentFrame - Current frame count used for forced updates.
	 * @param {Vector3} lightDirection - Current light direction.
	 * @param {number} maxShadowRays - Maximum shadow raycasts allowed for this frame.
	 
]]
local function updatePixel(pixelIdx, lightDirection, maxShadowRays)
	local pixel = pixelData[pixelIdx + 1]
	if not pixel then
		return nil
	end
	local rayResult = Workspace:Raycast(pixel.worldPosition, pixel.rayDirection * 150)
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
	local sceneChanged = hitInstance ~= pixel.lastHitInstance or hitMaterial ~= pixel.lastHitMaterial
	local lightChanged = not pixel.lastLightDirection or pixel.lastLightDirection.Unit:Dot(lightDirection.Unit) ~= 1
	if sceneChanged or lightChanged then
		pixel.lastHitInstance = hitInstance
		pixel.lastHitPosition = hitPosition
		pixel.lastHitMaterial = hitMaterial
		pixel.lastLightDirection = lightDirection
		didUpdateFrame = true
		if rayResult then
			local hitPoint = rayResult.Position
			local surfaceNormal = rayResult.Normal
			local _arg0_1 = surfaceNormal * 0.1
			local testPosition = hitPoint + _arg0_1
			local inShadow = isInShadow(testPosition, lightDirection, 300, maxShadowRays)
			if inShadow then
				local originalColor = rayResult.Instance.Color
				local blendAmount = 0.6
				local r = originalColor.R * 255 * (1 - blendAmount) + SHADOW_COLOR.R * blendAmount
				local g = originalColor.G * 255 * (1 - blendAmount) + SHADOW_COLOR.G * blendAmount
				local b = originalColor.B * 255 * (1 - blendAmount) + SHADOW_COLOR.B * blendAmount
				setPixelColor(pixelIdx, r, g, b)
			else
				local originalColor = rayResult.Instance.Color
				local r = math.min(255, originalColor.R * 255 * 0.3 + LIGHT_COLOR.R * 0.4)
				local g = math.min(255, originalColor.G * 255 * 0.3 + LIGHT_COLOR.G * 0.4)
				local b = math.min(255, originalColor.B * 255 * 0.3 + LIGHT_COLOR.B * 0.4)
				setPixelColor(pixelIdx, r, g, b)
			end
		else
			local r = SKYBOX_COLOR.R * (1 - 0.6) + LIGHT_COLOR.R * 0.6
			local g = SKYBOX_COLOR.G * (1 - 0.6) + LIGHT_COLOR.G * 0.6
			local b = SKYBOX_COLOR.B * (1 - 0.6) + LIGHT_COLOR.B * 0.6
			setPixelColor(pixelIdx, r, g, b)
		end
	end
end
--[[
	*
	 * Flushes all pixel data updates to the editable image for display.
	 * Uses WritePixelsBuffer for efficient bulk update.
	 
]]
local function flushPixelUpdates()
	editableImage:WritePixelsBuffer(Vector2.new(0, 0), Vector2.new(IMAGE_WIDTH, IMAGE_HEIGHT), pixelBuffer)
end
-- Initialize pixel positions centered at (0, 15, -30) with scale 0.5 (world units per pixel)
initializePixelData(Vector3.new(0, 15, -30), 0.5)
-- Main loop
RunService.Heartbeat:Connect(function(dT)
	refresh_timer += dT
	if refresh_timer < 1 / 30 then
		return nil
	end
	refresh_timer = 0
	shadowLimiter = 0
	globalFrameCount += 1
	didUpdateFrame = false
	local frameStartTime = tick()
	local lightDirection = getLightDirection()
	local shadowLimit = 400
	for i = 0, BATCH_SIZE - 1 do
		updatePixel(pixelIndex, lightDirection, shadowLimit)
		pixelIndex = (pixelIndex + 1) % TOTAL_PIXELS
	end
	if didUpdateFrame then
		flushPixelUpdates()
	end
	local frameTime = (tick() - frameStartTime) * 1000
	if frameTime > 2 then
		local frameTimeStr = string.format("%.2f", frameTime)
		print(`Frame took {frameTimeStr}ms`)
	end
end)
