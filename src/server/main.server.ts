import { Lighting, RunService, Workspace } from "@rbxts/services";

interface TrackedPart {
    part: BasePart;
    lastPos: Vector3;
    lastRot: Vector3; // Euler angles
    lastLook: Vector3;
}
// constants
const batchSize = 200;
const FORCE_UPDATE_INT = 15;
const allTrackedParts: TrackedPart[][] = [];
// shadow constants
const SHADOW_COLOR = Color3.fromRGB(50,50,100);
const LIGHT_COLOR = Color3.fromRGB(255,255,200);
const SHADOW_TRANSPARENCY = 0.01;
const LIGHT_TRANSPARENCY = 0;
// mutables
let index = 0;
let globalFrameCount = 0;
let refresh_timer = 0;

/** 
 *  @param {Vector3} a - 1st vector3
 *  @param {Vector3} b - 2nd vector3
 *  @param {number} [epsilon = 0.001] - optional param for tolerance threshold
 *  @returns {boolean} true/false
 */
function fuzzyEqual(a: Vector3,b: Vector3,epsilon = 0.001) {
    return math.abs(a.X - b.X) < epsilon
        && math.abs(a.Y - b.Y) < epsilon
        && math.abs(a.Z - b.Z) < epsilon;
}

/**
 * Get the primary light direction (from sun/directional light)
 * @returns {Vector3}
 */
function getLightDirection(): Vector3 {
    const sunDirection = Lighting.GetSunDirection();

    if (globalFrameCount % 60 === 0) {
        print(`Sun direction: ${sunDirection.X},${sunDirection.Y},${sunDirection.Z}`);
    }

    return sunDirection.Unit;
}

/**
 * Cast a shadow ray to detect if a point is in shadow
 * @param {Vector3} position  The position to check for shadows
 * @param {Vector3} lightDirection Direction towards light source 
 * @param {BasePart} sourcePart The part we're casting from
 * @param {number} maxDistance Maximum distance to cast the shadow ray
 * @returns {boolean} True if the point is in shadow
 */
function isInShadow(position: Vector3, lightDirection: Vector3,sourcePart: BasePart,maxDistance = 1000): boolean {
    const raycastParams = new RaycastParams();
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude;

    const rayModel = sourcePart.Parent;
    const filterList: Instance[] = [sourcePart];
    if (rayModel) {
        filterList.push(rayModel);
    }
    raycastParams.FilterDescendantsInstances = filterList;

    const offsetPos = position.add(lightDirection.Unit.mul(0.1));
    const shadowRay = Workspace.Raycast(offsetPos,lightDirection.mul(maxDistance),raycastParams);

    return shadowRay !== undefined;
}

/**
 * 
 * @param {number} x_parts nr of parts on the x-axis 
 * @param {number} y_parts nr of parts on the y-axis
 * @param {CFrame} position optional param for the position of the model
 * @returns {TrackedPart[]}
 */
function rayModel(x_parts: number, y_parts: number,position?: CFrame): TrackedPart[] {
    const model = new Instance("Model");
    model.Name = "RayModel";
    model.Parent = Workspace;
    if (position && typeOf(position) === "CFrame") {
        model.PivotTo(position)
    } else if (position && typeOf(position) !== "CFrame") {throw "position must be a CFrame"};

    const tracked: TrackedPart[] = [];
    for (let x = 0; x < x_parts; x++) {
        task.wait();
        for (let y = 0; y < y_parts; y++) {
            const part = new Instance("Part");
            part.Size = new Vector3(1, 1, 1);
            part.Position = new Vector3(x, y, 0);
            part.Anchored = true;
            part.Color = Color3.fromRGB(255, 0, 0);
            part.Parent = model;

            tracked.push({
                part,
                lastPos: part.Position,
                lastRot: part.Orientation,
                lastLook: part.CFrame.LookVector,
            });
        }
    }
    return tracked;
}

/**
 * 
 * @param {TrackedPart} data the data of the part
 * @param {number} currentFrame the current frame
 * @returns {void}
 */
function updatePart(data: TrackedPart,currentFrame: number) {
        const part = data.part;
        const pos = part.Position;
        const rot = part.Orientation;
        const look = part.CFrame.LookVector;

        const forceUpdate = currentFrame % FORCE_UPDATE_INT === 0;
        const moved = !fuzzyEqual(pos,data.lastPos) || !fuzzyEqual(rot,data.lastRot)  || !fuzzyEqual(look,data.lastLook) || forceUpdate;
        
        data.lastPos = pos;
        data.lastRot = rot;
        data.lastLook = look;

        if (moved) {
            const rayResult = Workspace.Raycast(pos,look.mul(100));
        if (rayResult) {
            const hitPoint = rayResult.Position;
            const surfaceNormal = rayResult.Normal;
            const lightDirection = getLightDirection();

            const testPosition = hitPoint.add(surfaceNormal.mul(0.1));
            const inShadow = isInShadow(testPosition,lightDirection,part);

            if (inShadow) {
                const originalColor = rayResult.Instance.Color;
                const blendAmount = 0.6;

                const r = originalColor.R * (1 - blendAmount) + SHADOW_COLOR.R * blendAmount;
                const g = originalColor.G * (1 - blendAmount) + SHADOW_COLOR.G * blendAmount;
                const b = originalColor.B * (1 - blendAmount) + SHADOW_COLOR.B * blendAmount;

                part.Color = new Color3(r,g,b);
                part.Transparency = SHADOW_TRANSPARENCY;
                part.Material = rayResult.Instance.Material;
            } else {
                const originalColor = rayResult.Instance.Color;

                const r = math.min(1, originalColor.R * 0.7 + LIGHT_COLOR.R * 0.3);
                const g = math.min(1, originalColor.G * 0.7 + LIGHT_COLOR.G * 0.3);
                const b = math.min(1, originalColor.B * 0.7 + LIGHT_COLOR.B * 0.3);

                part.Color = Color3.fromRGB(r * 255,g * 255,b * 255);
                part.Transparency = LIGHT_TRANSPARENCY;
                part.Material = rayResult.Instance.Material;
            }
        } else {part.Transparency = 1;}
    }
}


allTrackedParts.push(rayModel(70,35,new CFrame(0,0,0)))

RunService.Heartbeat.Connect((dT) => {
    refresh_timer += dT;
    if (refresh_timer < 1/20) return;
    refresh_timer = 0;
    globalFrameCount++;
    const isForceUpdateFrame = globalFrameCount % FORCE_UPDATE_INT === 0;
    if (isForceUpdateFrame) {
        const trackedParts = allTrackedParts[0];
        for (let i = 0; i < trackedParts.size(); i++) {
            updatePart(trackedParts[i],globalFrameCount);
        }
    } else {
        for (let i = 0; i < batchSize; i++) {
        const trackedParts = allTrackedParts[0];
        const data = trackedParts[index];
        updatePart(data,globalFrameCount);
        index = (index + 1) % trackedParts.size();
        }
    }
});
