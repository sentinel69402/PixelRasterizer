import { RunService, Workspace } from "@rbxts/services";

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
// mutables
let index = 0;
let globalFrameCount = 0;
let refresh_timer = 0;

/** 
 *  @param {Vector3} a - 1st vector3
 *  @param {Vector3} b - 2nd vector3
 *  @param {number} [epsilon = 0.001] - optional param for tolerance threshold
 *  @returns {boolean}
 */
function fuzzyEqual(a: Vector3,b: Vector3,epsilon = 0.001) {
    return math.abs(a.X - b.X) < epsilon
        && math.abs(a.Y - b.Y) < epsilon
        && math.abs(a.Z - b.Z) < epsilon;
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
            part.Transparency = 0;
            part.Color = rayResult.Instance.Color;
        } else {part.Transparency = 1;}
    }
}


allTrackedParts.push(rayModel(60,20,new CFrame(0,0,0)))

RunService.Heartbeat.Connect((dT) => {
    refresh_timer += dT;
    if (refresh_timer < 1/15) return;
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
