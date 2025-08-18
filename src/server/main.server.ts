import { Lighting, RunService, Workspace } from "@rbxts/services";

interface TrackedPart {
    part: BasePart;
    lastHitInstance: Instance | undefined;
    lastHitPosition: Vector3 | undefined;
    lastHitMaterial: Enum.Material | undefined;
    lastLightDirection: Vector3 | undefined;
}

interface partUpdate {
    part: BasePart,
    color: Color3,
    transparency: number,
    material: Enum.Material,
}

// constants
const batchSize = 200;
const FORCE_UPDATE_INT = 10;
const allTrackedParts: TrackedPart[][] = [];
const raycastParams = new RaycastParams();
const filterList: Instance[] = [];
raycastParams.FilterType = Enum.RaycastFilterType.Exclude;
const skybox = true;
const skyboxColor = Color3.fromRGB(51,168,247);
// batch updates
const MAX_PARTS = 100000;
const BYTES_PER_PART = 20;
const updateBuffer = buffer.create(MAX_PARTS * BYTES_PER_PART);
const partIndexMap = new Map<BasePart,number>();
const dirtyParts = new Set<number>();
let nextPartIndex = 0;
// shadow constants
const SHADOW_COLOR = Color3.fromRGB(50,50,100);
const LIGHT_COLOR = Color3.fromRGB(255,255,200);
const SHADOW_TRANSPARENCY = 0.01;
const LIGHT_TRANSPARENCY = 0;

// mutables
let index = 0;
let globalFrameCount = 0;
let refresh_timer = 0;
let shadowLimiter = 0;

/** 
 *  @param {Vector3} a - 1st vector3
 *  @param {Vector3} b - 2nd vector3
 *  @param {number} [epsilon = 0.001] - optional param for tolerance threshold
 *  @returns {boolean} true/false
 */
function fuzzyEqual(a: Vector3, b: Vector3, epsilon = 0.001) {
    return math.abs(a.X - b.X) < epsilon
        && math.abs(a.Y - b.Y) < epsilon
        && math.abs(a.Z - b.Z) < epsilon;
}

function fuzzyColorEq(a: Color3, b: Color3, epsilon = 0.01) {
    return math.abs(a.R - b.R) < epsilon 
        && math.abs(a.G - b.G) < epsilon
        && math.abs(a.B - b.B) < epsilon;
}

/**
 * Get the primary light direction (from sun/directional light)
 * @returns {Vector3}
 */
function getLightDirection(): Vector3 {
    const sunDirection = Lighting.GetSunDirection();
    return sunDirection.Unit;
}

function getPartIndex(part: BasePart): number {
    let index = partIndexMap.get(part);
    if (index === undefined) {
        index = nextPartIndex++;
        partIndexMap.set(part,index);
    }
    return index;
}

function materialToNumber(material: Enum.Material): number {
    return material.Value || 0;
}

function numberToMaterial(value: number): Enum.Material {
    for (const [_, material] of pairs(Enum.Material.GetEnumItems())) {
        if (material.Value === value) {
            return material;
        }
    }
    return Enum.Material.SmoothPlastic; 
}

function bufferPartUpdate(part: BasePart,color: Color3,transparency: number,material: Enum.Material) {
    const partIndex = getPartIndex(part);
    const offset = partIndex * BYTES_PER_PART;
    
    const currentR = buffer.readf32(updateBuffer, offset);
    const currentG = buffer.readf32(updateBuffer, offset + 4);
    const currentB = buffer.readf32(updateBuffer, offset + 8);
    const currentA = buffer.readf32(updateBuffer, offset + 12);
    const currentMat = buffer.readi32(updateBuffer, offset + 16);
    
    const materialNum = materialToNumber(material);
    
    const needsUpdate = math.abs(currentR - color.R) > 0.01 ||
                       math.abs(currentG - color.G) > 0.01 ||
                       math.abs(currentB - color.B) > 0.01 ||
                       math.abs(currentA - transparency) > 0.001 ||
                       currentMat !== materialNum;
    
    if (needsUpdate) {
        buffer.writef32(updateBuffer, offset, color.R);
        buffer.writef32(updateBuffer, offset + 4, color.G);
        buffer.writef32(updateBuffer, offset + 8, color.B);
        buffer.writef32(updateBuffer, offset + 12, transparency);
        buffer.writei32(updateBuffer, offset + 16, materialNum);
        
        dirtyParts.add(partIndex);
    }
}

function flushBufferedUpdates() {
    if (dirtyParts.size() === 0) return;
    
    const startTime = tick();
    let updatedCount = 0;
    
    for (const partIndex of dirtyParts) {
        let targetPart: BasePart | undefined;
        for (const [part, index] of partIndexMap) {
            if (index === partIndex) {
                targetPart = part;
                break;
            }
        }
        
        if (targetPart) {
            const offset = partIndex * BYTES_PER_PART;
            
            const newR = buffer.readf32(updateBuffer, offset);
            const newG = buffer.readf32(updateBuffer, offset + 4);
            const newB = buffer.readf32(updateBuffer, offset + 8);
            const newTransparency = buffer.readf32(updateBuffer, offset + 12);
            const newMaterialNum = buffer.readi32(updateBuffer, offset + 16);
            
            const newColor = new Color3(newR, newG, newB);
            const newMaterial = numberToMaterial(newMaterialNum);
            
            if (!fuzzyColorEq(targetPart.Color, newColor)) {
                targetPart.Color = newColor;
            }
            if (targetPart.Transparency !== newTransparency) {
                targetPart.Transparency = newTransparency;
            }
            if (targetPart.Material !== newMaterial) {
                targetPart.Material = newMaterial;
            }
            
            updatedCount++;
        }
    }
    
    const updateTime = (tick() - startTime) * 1000;
    if (updatedCount > 50) {
        const timeStr = string.format("%.2f", updateTime);
        print(`Buffered updated ${updatedCount} parts in ${timeStr}ms`);
    }
    
    dirtyParts.clear();
}

/**
 * Cast a shadow ray to detect if a point is in shadow
 * @param {Vector3} position  The position to check for shadows
 * @param {Vector3} lightDirection Direction towards light source 
 * @param {BasePart} sourcePart The part we're casting from
 * @param {number} maxDistance Maximum distance to cast the shadow ray
 * @param {number} maxShadowRays Maximum shadow rays allowed this frame
 * @returns {boolean} True if the point is in shadow
 */
function isInShadow(position: Vector3, lightDirection: Vector3, sourcePart: BasePart, maxDistance = 300, maxShadowRays: number): boolean {
    if (shadowLimiter >= maxShadowRays) return false;
    shadowLimiter++;
    
    const rayModel = sourcePart.Parent;
    filterList.clear();
    if (sourcePart && rayModel) {
        filterList.push(sourcePart);
        filterList.push(rayModel);
    }
    raycastParams.FilterDescendantsInstances = filterList;

    const offsetPos = position.add(lightDirection.Unit.mul(0.1));
    const shadowRay = Workspace.Raycast(offsetPos, lightDirection.mul(maxDistance), raycastParams);

    return shadowRay !== undefined;
}

/**
 * Create a grid of raycast parts for lighting analysis
 * @param {number} x_parts nr of parts on the x-axis 
 * @param {number} y_parts nr of parts on the y-axis
 * @param {CFrame} position optional param for the position of the model
 * @returns {TrackedPart[]}
 */
function rayModel(x_parts: number, y_parts: number, position?: CFrame): TrackedPart[] {
    const model = new Instance("Model");
    model.Name = "RayModel";
    model.Parent = Workspace;
    if (position && typeOf(position) === "CFrame") {
        model.PivotTo(position)
    } else if (position && typeOf(position) !== "CFrame") {
        throw "position must be a CFrame";
    }

    const tracked: TrackedPart[] = [];
    for (let x = 0; x < x_parts; x++) {
        for (let y = 0; y < y_parts; y++) {
            const part = new Instance("Part");
            part.Size = new Vector3(1, 1, 1);
            part.Position = new Vector3(x, y, 0);
            part.Anchored = true;
            part.CastShadow = false;
            part.CanCollide = false;
            part.Color = Color3.fromRGB(255, 0, 0);
            part.Parent = model;

            tracked.push({
                part,
                lastHitInstance: undefined,
                lastHitPosition: undefined,
                lastHitMaterial: undefined,
                lastLightDirection: undefined,
            });
        }
    }
    return tracked;
}

/**
 * Update a single tracked part with lighting information
 * @param {TrackedPart} data the data of the part
 * @param {number} currentFrame the current frame
 * @param {Vector3} lightDirection current light direction
 * @param {number} maxShadowRays maximum shadow rays for this update cycle
 * @returns {void}
 */
function updatePart(data: TrackedPart, currentFrame: number, lightDirection: Vector3, maxShadowRays: number) {
    const part = data.part;
    const rayResult = Workspace.Raycast(part.Position, part.CFrame.LookVector.mul(100));
    
    const forceUpdate = currentFrame % FORCE_UPDATE_INT === 0;
    
    const hitInstance = rayResult?.Instance;
    const hitPosition = rayResult?.Position;
    const hitMaterial = rayResult?.Instance?.Material;
    
    const sceneChanged = hitInstance !== data.lastHitInstance ||
                        (hitPosition && data.lastHitPosition && !fuzzyEqual(hitPosition, data.lastHitPosition)) ||
                        (hitPosition && !data.lastHitPosition) ||
                        (!hitPosition && data.lastHitPosition) ||
                        hitMaterial !== data.lastHitMaterial;
    
    const lightChanged = !data.lastLightDirection || !fuzzyEqual(lightDirection,data.lastLightDirection);
    
    data.lastHitInstance = hitInstance;
    data.lastHitPosition = hitPosition;
    data.lastHitMaterial = hitMaterial;
    data.lastLightDirection = lightDirection;
    
    if (sceneChanged || lightChanged) {
        if (rayResult) {
            const hitPoint = rayResult.Position;
            const surfaceNormal = rayResult.Normal;

            const testPosition = hitPoint.add(surfaceNormal.mul(0.1));
            const inShadow = isInShadow(testPosition, lightDirection, part, 300, maxShadowRays);

            if (inShadow) {
                const originalColor = rayResult.Instance.Color;
                const blendAmount = 0.6;

                const r = originalColor.R * (1 - blendAmount) + SHADOW_COLOR.R * blendAmount;
                const g = originalColor.G * (1 - blendAmount) + SHADOW_COLOR.G * blendAmount;
                const b = originalColor.B * (1 - blendAmount) + SHADOW_COLOR.B * blendAmount;
                const newColor = new Color3(r, g, b);
                
                bufferPartUpdate(part,newColor,SHADOW_TRANSPARENCY,rayResult.Instance.Material);
            } else {
                const originalColor = rayResult.Instance.Color;

                const r = math.min(1, originalColor.R * 0.3 + LIGHT_COLOR.R * 0.4);
                const g = math.min(1, originalColor.G * 0.3 + LIGHT_COLOR.G * 0.4);
                const b = math.min(1, originalColor.B * 0.3 + LIGHT_COLOR.B * 0.4);
                const newColor = Color3.fromRGB(r * 255, g * 255, b * 255);
                
                bufferPartUpdate(part,newColor,LIGHT_TRANSPARENCY,rayResult.Instance.Material);
            }
        } else {
            if (skybox) {
                const r = skyboxColor.R * (1 - 0.6) + LIGHT_COLOR.R * 0.6;
                const g = skyboxColor.G * (1 - 0.6) + LIGHT_COLOR.G * 0.6;
                const b = skyboxColor.B * (1 - 0.6) + LIGHT_COLOR.B * 0.6;
                const skyColor = Color3.fromRGB(r * 255,g * 255,b * 255);

                bufferPartUpdate(part,skyColor,0,Enum.Material.SmoothPlastic);
            } else {bufferPartUpdate(part,part.Color,1,part.Material);}
        }
    }
}

allTrackedParts.push(rayModel(70, 64, new CFrame(0, 0, 0)));

RunService.Heartbeat.Connect((dT) => {
    refresh_timer += dT;
    if (refresh_timer < 1/20) return;
    refresh_timer = 0;
    shadowLimiter = 0;
    globalFrameCount++;
    const lightDirection = getLightDirection();

    const frameStartTime = tick();

    const isForceUpdateFrame = globalFrameCount % FORCE_UPDATE_INT === 0;

    if (isForceUpdateFrame) {
        const trackedParts = allTrackedParts[0];
        const maxForceUpdates = 500;
        const shadowLimit = 500;
        for (let i = 0; i < math.min(trackedParts.size(), maxForceUpdates); i++) {
            updatePart(trackedParts[i], globalFrameCount, lightDirection, shadowLimit);
        }
    } else {
        const shadowLimit = 200;
        for (let i = 0; i < batchSize; i++) {
            const trackedParts = allTrackedParts[0];
            const data = trackedParts[index];
            updatePart(data, globalFrameCount, lightDirection, shadowLimit);
            index = (index + 1) % trackedParts.size();
        }
    }

    flushBufferedUpdates();

    const frameTime = (tick() - frameStartTime) * 1000;
    if (frameTime > 10) {
        const frameTimeStr = string.format("%.2f",frameTime);
        print(`Frame took ${frameTimeStr}ms, updated ${dirtyParts.size()} parts`);
    }
});