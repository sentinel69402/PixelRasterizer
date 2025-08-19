import { Lighting, Players, RunService, Workspace } from "@rbxts/services";


/**
 * Represents a pixel used for lighting analysis in the world.
 * @property {Vector3} worldPosition - The world position corresponding to the pixel.
 * @property {Vector3} rayDirection - The direction to cast rays for this pixel.
 * @property {Instance | undefined} lastHitInstance - Last instance hit by raycast.
 * @property {Vector3 | undefined} lastHitPosition - Last hit position from raycast.
 * @property {Enum.Material | undefined} lastHitMaterial - Last material hit.
 * @property {Vector3 | undefined} lastLightDirection - Last used light direction.
 */
interface LightingPixel {
    worldPosition: Vector3;
    rayDirection: Vector3;
    lastHitInstance: Instance | undefined;
    lastHitPosition: Vector3 | undefined;
    lastHitMaterial: Enum.Material | undefined;
    lastLightDirection: Vector3 | undefined;
}

// Constants for image size and performance tuning
const IMAGE_WIDTH = 100;
const IMAGE_HEIGHT = 60;
const TOTAL_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;
const FORCE_UPDATE_INT = 10; // Frames between forced updates
const BATCH_SIZE = 400; // number of pixels updated per frame 

// Create EditableImage
const AssetService = game.GetService("AssetService");
const editableImage = AssetService.CreateEditableImage({
    Size: new Vector2(IMAGE_WIDTH, IMAGE_HEIGHT)
});

// Image Label to display the EditableImage
const imageLabel = new Instance("ImageLabel");
imageLabel.Size = new UDim2(0.5, 0, 0.5, 0);
imageLabel.ImageContent = Content.fromObject(editableImage);

// ScreenGui to hold the Image Label
const screenGui = new Instance("ScreenGui");
screenGui.Parent = Players.LocalPlayer!.WaitForChild("PlayerGui");
imageLabel.Parent = screenGui;

// Storage for pixel data and pixel color buffer
const pixelData: LightingPixel[] = [];
const pixelBuffer = buffer.create(TOTAL_PIXELS * 4); // RGBA, 1 byte per channel
const raycastParams = new RaycastParams();
raycastParams.FilterType = Enum.RaycastFilterType.Exclude;

// Predefined colors used for shadows, light, and skybox
const SHADOW_COLOR = { R: 50, G: 50, B: 100 };
const LIGHT_COLOR = { R: 255, G: 255, B: 200 };
const SKYBOX_COLOR = { R: 51, G: 168, B: 247 };

// State tracking variables
let pixelIndex = 0;
let globalFrameCount = 0;
let refresh_timer = 0;
let shadowLimiter = 0;

/**
 * Initializes pixel data array with world positions and ray directions.
 * @param {Vector3} centerPosition - The central world position for the pixel grid.
 * @param {number} scale - Distance between adjacent pixels in world units.
 */
function initializePixelData(centerPosition: Vector3, scale: number = 1) {
    pixelData.clear();
    
    for (let y = 0; y < IMAGE_HEIGHT; y++) {
        for (let x = 0; x < IMAGE_WIDTH; x++) {
            const worldX = centerPosition.X - (x - IMAGE_WIDTH / 2) * scale;
            const worldY = centerPosition.Y - (y - IMAGE_HEIGHT / 2) * scale;
            const worldZ = centerPosition.Z;
            
            pixelData.push({
                worldPosition: new Vector3(worldX, worldY, worldZ),
                rayDirection: new Vector3(0, 0, 1),
                lastHitInstance: undefined,
                lastHitPosition: undefined,
                lastHitMaterial: undefined,
                lastLightDirection: undefined,
            });
        }
    }
}

/**
 * Converts 2D pixel coordinates to a linear index in the pixel buffer.
 * Y coordinate is flipped to match image orientation.
 * @param {number} x - The x coordinate of the pixel.
 * @param {number} y - The y coordinate of the pixel.
 * @returns {number} The linear pixel index.
 */
function worldToPixel(x: number, y: number): number {
    const flippedY = IMAGE_HEIGHT - 1 - y;
    return flippedY * IMAGE_WIDTH + x;
}

/**
 * Writes RGBA color values into the pixel buffer at the specified pixel index.
 * @param {number} pixelIndex - Index of the pixel to update.
 * @param {number} r - Red channel value (0-255).
 * @param {number} g - Green channel value (0-255).
 * @param {number} b - Blue channel value (0-255).
 * @param {number} [a=255] - Alpha channel value (default 255, fully opaque).
 */
function setPixelColor(pixelIndex: number, r: number, g: number, b: number, a: number = 255) {
    const offset = pixelIndex * 4;
    buffer.writeu8(pixelBuffer, offset, math.floor(r));
    buffer.writeu8(pixelBuffer, offset + 1, math.floor(g));
    buffer.writeu8(pixelBuffer, offset + 2, math.floor(b));
    buffer.writeu8(pixelBuffer, offset + 3, math.floor(a));
}

/**
 * Retrieves the primary sunlight direction in the game world.
 * @returns {Vector3} Unit vector representing sun direction.
 */
function getLightDirection(): Vector3 {
    return Lighting.GetSunDirection().Unit;
}

/**
 * Casts a shadow ray from a given position towards the light direction to check for shadows.
 * Limits the number of shadow rays per frame to control performance.
 * @param {Vector3} position - World position to start the shadow ray.
 * @param {Vector3} lightDirection - Direction of the light (unit vector).
 * @param {number} [maxDistance=300] - Maximum raycast distance.
 * @param {number} maxShadowRays - Maximum allowed shadow rays per frame.
 * @returns {boolean} True if the position is in shadow, false otherwise.
 */
function isInShadow(position: Vector3, lightDirection: Vector3, maxDistance = 300, maxShadowRays: number): boolean {
    if (shadowLimiter >= maxShadowRays) return false;
    shadowLimiter++;
    
    const offsetPos = position.add(lightDirection.Unit.mul(0.1));
    const shadowRay = Workspace.Raycast(offsetPos, lightDirection.mul(maxDistance), raycastParams);
    return shadowRay !== undefined;
}

/**
 * Updates the lighting data for a single pixel by raycasting and color blending.
 * Applies shadow and light blending depending on occlusion.
 * Caches last hit data to optimize updates.
 * @param {number} pixelIdx - Index of the pixel in the pixelData array.
 * @param {number} currentFrame - Current frame count used for forced updates.
 * @param {Vector3} lightDirection - Current light direction.
 * @param {number} maxShadowRays - Maximum shadow raycasts allowed for this frame.
 */
function updatePixel(pixelIdx: number, currentFrame: number, lightDirection: Vector3, maxShadowRays: number) {
    const pixel = pixelData[pixelIdx];
    if (!pixel) return;
    
    const rayResult = Workspace.Raycast(pixel.worldPosition, pixel.rayDirection.mul(100));
    
    const forceUpdate = currentFrame % FORCE_UPDATE_INT === 0;
    
    const hitInstance = rayResult?.Instance;
    const hitPosition = rayResult?.Position;
    const hitMaterial = rayResult?.Instance?.Material;
    
    const sceneChanged = hitInstance !== pixel.lastHitInstance ||
                        hitMaterial !== pixel.lastHitMaterial;
    
    const lightChanged = !pixel.lastLightDirection || 
                         pixel.lastLightDirection.Unit.Dot(lightDirection.Unit) !== 1;
    
    // Update cached data
    pixel.lastHitInstance = hitInstance;
    pixel.lastHitPosition = hitPosition;
    pixel.lastHitMaterial = hitMaterial;
    pixel.lastLightDirection = lightDirection;
    
    if (sceneChanged || lightChanged || forceUpdate) {
        if (rayResult) {
            const hitPoint = rayResult.Position;
            const surfaceNormal = rayResult.Normal;
            
            const testPosition = hitPoint.add(surfaceNormal.mul(0.1));
            const inShadow = isInShadow(testPosition, lightDirection, 300, maxShadowRays);
            
            if (inShadow) {
                const originalColor = rayResult.Instance.Color;
                const blendAmount = 0.6;
                
                const r = originalColor.R * 255 * (1 - blendAmount) + SHADOW_COLOR.R * blendAmount;
                const g = originalColor.G * 255 * (1 - blendAmount) + SHADOW_COLOR.G * blendAmount;
                const b = originalColor.B * 255 * (1 - blendAmount) + SHADOW_COLOR.B * blendAmount;
                
                setPixelColor(pixelIdx, r, g, b);
            } else {
                const originalColor = rayResult.Instance.Color;
                
                const r = math.min(255, originalColor.R * 255 * 0.3 + LIGHT_COLOR.R * 0.4);
                const g = math.min(255, originalColor.G * 255 * 0.3 + LIGHT_COLOR.G * 0.4);
                const b = math.min(255, originalColor.B * 255 * 0.3 + LIGHT_COLOR.B * 0.4);
                
                setPixelColor(pixelIdx, r, g, b);
            }
        } else {
            const r = SKYBOX_COLOR.R * (1 - 0.6) + LIGHT_COLOR.R * 0.6;
            const g = SKYBOX_COLOR.G * (1 - 0.6) + LIGHT_COLOR.G * 0.6;
            const b = SKYBOX_COLOR.B * (1 - 0.6) + LIGHT_COLOR.B * 0.6;
            
            setPixelColor(pixelIdx, r, g, b);
        }
    }
}

/**
 * Flushes all pixel data updates to the editable image for display.
 * Uses WritePixelsBuffer for efficient bulk update.
 */
function flushPixelUpdates() {
    editableImage.WritePixelsBuffer(
        new Vector2(0, 0),
        new Vector2(IMAGE_WIDTH, IMAGE_HEIGHT),
        pixelBuffer
    );
}

// Initialize pixel positions centered at (0, 15, -30) with scale 0.5 (world units per pixel)
initializePixelData(new Vector3(0, 15, -30), 0.5);

// Main loop
RunService.Heartbeat.Connect((dT) => {
    refresh_timer += dT;
    if (refresh_timer < 1/20) return; // 60 FPS for smooth image updates
    refresh_timer = 0;
    shadowLimiter = 0;
    globalFrameCount++;
    
    const frameStartTime = tick();
    const lightDirection = getLightDirection();
    
    const isForceUpdateFrame = globalFrameCount % FORCE_UPDATE_INT === 0;
    
    if (isForceUpdateFrame) {
        const maxForceUpdates = 500;
        const shadowLimit = 200;
        
        for (let i = 0; i < math.min(TOTAL_PIXELS, maxForceUpdates); i++) {
            updatePixel(i, globalFrameCount, lightDirection, shadowLimit);
        }
    } else {
        const shadowLimit = 400;
        
        for (let i = 0; i < BATCH_SIZE; i++) {
            updatePixel(pixelIndex, globalFrameCount, lightDirection, shadowLimit);
            pixelIndex = (pixelIndex + 1) % TOTAL_PIXELS;
        }
    }
    
    flushPixelUpdates();
    
    const frameTime = (tick() - frameStartTime) * 1000;
    if (frameTime > 5) {
        const frameTimeStr = string.format("%.2f", frameTime);
        print(`Frame took ${frameTimeStr}ms`);
    }
});