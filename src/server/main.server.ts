import { RunService, Workspace } from "@rbxts/services";

interface TrackedPart {
    part: BasePart;
    lastPos: Vector3;
    lastRot: Vector3; // Euler angles
    lastLook: Vector3;
}

function vectorsEqual(a: Vector3, b: Vector3) {
    return a.X === b.X && a.Y === b.Y && a.Z === b.Z;
}

function fuzzyEqual(a: Vector3,b: Vector3,epsilon = 0.001) {
    return math.abs(a.X - b.X) < epsilon
        && math.abs(a.Y - b.Y) < epsilon
        && math.abs(a.Z - b.Z) < epsilon;
}

function rayModel(x_parts: number, y_parts: number): TrackedPart[] {
    const model = new Instance("Model");
    model.Name = "RayModel";
    model.Parent = Workspace;

    const tracked: TrackedPart[] = [];
    for (let x = 0; x < x_parts; x++) {
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

const trackedParts = rayModel(60,20);
const batchSize = 200;
let index = 0;

RunService.Stepped.Connect(() => {
    for (let i = 0; i < batchSize; i++) {
        const data = trackedParts[index];
        const part = data.part;
        const pos = part.Position;
        const rot = part.Orientation;
        const look = part.CFrame.LookVector;

        const moved = !fuzzyEqual(pos,data.lastPos) || !fuzzyEqual(rot,data.lastRot)  || !fuzzyEqual(look,data.lastLook);

        data.lastPos = pos;
        data.lastRot = rot;
        data.lastLook = look;

        if (moved || true) {
            const rayResult = Workspace.Raycast(pos,look.mul(100));
            if (rayResult) {
                part.Transparency = 0;
                part.Color = rayResult.Instance.Color;
            } else {part.Transparency = 1;}
        }
        index = (index + 1) % trackedParts.size();
    }   
});
