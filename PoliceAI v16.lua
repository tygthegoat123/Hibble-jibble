-- Police AI v17 (client-sided, self-building)
-- Officer drives the police car (13573040423) ON ROADS, chases other players (never you),
-- carries a pistol (5268138684) and an MP9 (117326611764505) with ammo, reloads and sounds.
-- v16: SWAT car front flipped, helicopter fires heat-seeking missiles.
-- v17: new police car rig with suspension + rotating/steering wheels, wail/yelp sirens.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local playerChar = player.Character or player.CharacterAdded:Wait()
local playerRoot = playerChar:WaitForChild("HumanoidRootPart")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local CAR_ID = 13573040423
local SIREN_WAIL_ID = 89059022469518
local SIREN_YELP_ID = 110601329618001
local SIREN_WAIL_TIME = 7 -- seconds of wail before switching to yelp
local SIREN_YELP_TIME = 4
local SUSP_TRAVEL = 0.9 -- how far each wheel can move up/down (studs)
local SUSP_DAMP = 12 -- higher = less bouncy
local MAX_STEER_ANGLE = 0.45 -- front wheel turn (radians)
local LEAN_CORNER = 0.06 -- body roll in corners
local WHEEL_RIDE = 0.55 -- wheel centre height above the body bottom, in wheel radii (raise if the car sits too low)
local WHEEL_Y_ADJUST = 0 -- extra studs to move snapped wheels up (+) or down (-)
local CAR_UPSIDE_DOWN = nil -- nil = auto-detect; set true/false to force the rig upright if it still comes out flipped
local CAR_REVERSE_FRONT = true -- true if the police car drives backwards (applies to the police car only, not the SWAT car)
local MAX_SPEED = 90
local ACCEL = 70
local TURN_RATE = 2.4
local CLIMB_BOOST = 2.5 -- extra engine power on slopes
local DRIVER_UP = 1
local OFFROAD_DIST = 60 -- within this distance of the target the car may leave the road
local chaseNPCs = false -- toggled by GUI
local ENGINE_SOUND_ID = 137048982817372
local REINFORCE_MAX = 6 -- max officers alive at once (including the first)
local REINFORCE_COOLDOWN = 12 -- seconds between backup calls
local targetPlayer = nil -- set by the GUI; nil = any other player
local targetMe = false -- "Target Me" button: police treat YOU as a suspect too
local activeOfficers = 0
local lastBackup = 0
local runOfficer -- forward declaration

local AGGRESSION = 1.5 -- officers fire faster and drive harder (1 = old behaviour)
-- police helicopters
local HELI_ID = 6858256343
local HELI_MAX = 2 -- max helicopters at once
local HELI_DELAY = 25 -- seconds into a chase before a helicopter is called in
local HELI_SPEED = 110
local HELI_ALT = 70 -- cruise height above the target
local HELI_RADIUS = 70 -- orbit radius around the target
local HELI_HEALTH = 500 -- total damage your guns need to shoot it down
local HELI_REVERSE_FRONT = true -- flipped because the model's nose was backwards; set false to undo
local activeHelis = 0
local lastHeli = 0
-- heli heat-seeking missiles
local MISSILE_MODEL = 32686992
local MISSILE_LAUNCH_SND = 80568077150111
local MISSILE_THRUST_SND = 77246158727159
local MISSILE_EXPLODE_SND = 139900006476219
local MISSILE_SPEED = 130
local MISSILE_TURN = 3.2 -- homing strength
local MISSILE_LIFETIME = 9
local MISSILE_RANGE = 350
local MISSILE_COOLDOWN = 7
local MISSILE_SALVO = 2
local MISSILE_ROT = CFrame.Angles(0, 0, 0) -- if the model flies sideways/backwards try CFrame.Angles(0, math.rad(180), 0) or (math.rad(90), 0, 0)
-- SWAT unit
local SWAT_CAR_ID = 9535085961
local SWAT_REVERSE_FRONT = true -- flips the SWAT car's front; set false to undo
local SOLDIER_RIG_ID = 13769728016
local SWAT_COUNT = 12 -- soldiers that come out of the car
local SWAT_DELAY = 40 -- seconds into a chase before a SWAT car is sent
local SWAT_MAX = 2 -- max SWAT cars at once
local activeSwat = 0
local lastSwat = 0

-- what counts as a road (Concrete is left out on purpose: sidewalks). Parts named like roads count too.
local ROAD_MATS = {
	[Enum.Material.Asphalt] = true,
	[Enum.Material.Pavement] = true,
}
-- Road detection also works by COLOR: dark gray/black surfaces and thin white/yellow lane paint count as road.
-- Add exact road colors here if your map uses unusual ones, e.g. {Color3.fromRGB(60, 60, 65)}
local ROAD_COLORS = {}
local USE_COLOR_DETECTION = true
local learnedRoads = {} -- filled by the "Learn Road Here" button
local NOT_ROAD_MATS = {
	[Enum.Material.Grass] = true, [Enum.Material.LeafyGrass] = true, [Enum.Material.Sand] = true,
	[Enum.Material.Ground] = true, [Enum.Material.Mud] = true, [Enum.Material.Snow] = true,
	[Enum.Material.Ice] = true, [Enum.Material.Glacier] = true, [Enum.Material.Salt] = true,
	[Enum.Material.Sandstone] = true, [Enum.Material.Rock] = true, [Enum.Material.Basalt] = true,
	[Enum.Material.Limestone] = true, [Enum.Material.Wood] = true, [Enum.Material.WoodPlanks] = true,
	[Enum.Material.Fabric] = true, [Enum.Material.Water] = true,
}
local ROAD_NAMES = {"road", "street", "asphalt", "highway", "lane", "pavement", "intersection", "crosswalk"}

local GUN_HOLD_ID = "rbxassetid://277780478"
local STAB_ID = "rbxassetid://94161088"
local RELOAD_ANIM_ID = "rbxassetid://94332664"

local MP9_SCALE = 1.5 -- MP9 size multiplier (1 = original)
local MP9_FORWARD = 0.6 -- studs to push the MP9 forward in the hand

-- how each weapon sits in the right hand (rotate if a model points the wrong way)
local GRIP_PISTOL = CFrame.new(0, -0.9, 0) * CFrame.Angles(math.rad(-90), 0, 0)
local GRIP_MP9 = CFrame.new(0, -0.9 - MP9_FORWARD, 0) * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.Angles(0, math.rad(180), 0) -- flipped 180 so the barrel points forward

local WEAPON_DEFS = {
	pistol = {model = 5268138684, fire = 9205598207, reload = 138248399002834, grip = GRIP_PISTOL,
		magSize = 12, reserveMax = 84, dmgMin = 18, dmgMax = 28, rof = 0.35, burst = 1, spacing = 0, reloadTime = 1.8},
	mp9 = {model = 117326611764505, fire = 135089124824269, reload = 101495984355760, grip = GRIP_MP9,
		scale = MP9_SCALE, magSize = 30, reserveMax = 150, dmgMin = 9, dmgMax = 15, rof = 0.5, burst = 5, spacing = 0.07, reloadTime = 2.4},
}

----------------------------------------------------------------
-- helpers
----------------------------------------------------------------
local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local function weld(a, b)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
	return w
end

local function dist(a, b) return (a.Position - b.Position).Magnitude end
local function flat(v)
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 0.001 and f.Unit or Vector3.new(0, 0, -1)
end

local function isSuspect(model)
	if not model or model:GetAttribute("Police") then return false end
	if model == playerChar then return targetMe end
	local plr = Players:GetPlayerFromCharacter(model)
	if targetPlayer then return plr == targetPlayer end -- a chosen target overrides everything
	if plr then return true end
	return chaseNPCs
end

local function playSound(id, parent, vol)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = vol or 1
	s.RollOffMaxDistance = 250
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 5)
end

----------------------------------------------------------------
-- weapon loader (game:GetObjects, falls back to a plain block gun)
----------------------------------------------------------------
local function loadWeapon(id, label, scale)
	local container = Instance.new("Model")
	container.Name = label
	local handle

	local ok, objs = pcall(function() return game:GetObjects("rbxassetid://" .. id) end)
	if ok and objs and objs[1] then
		local src = objs[1]
		local parts = {}
		if src:IsA("BasePart") then table.insert(parts, src) end
		for _, d in ipairs(src:GetDescendants()) do
			if d:IsA("BasePart") then table.insert(parts, d) end
		end
		for _, p in ipairs(parts) do p.Parent = container end
		for _, d in ipairs(container:GetDescendants()) do
			if d:IsA("BaseScript") or d:IsA("Sound") then d:Destroy() end
		end
		src:Destroy()
		handle = container:FindFirstChild("Handle")
		if not handle then
			local bestV = 0
			for _, p in ipairs(container:GetChildren()) do
				if p:IsA("BasePart") then
					local v = p.Size.X * p.Size.Y * p.Size.Z
					if v > bestV then handle, bestV = p, v end
				end
			end
		end
	end
	if not handle then
		warn(label .. " model failed to load, using a block gun")
		handle = mk("Part", {Name = "Handle", Size = Vector3.new(0.2, 0.5, 0.9), Color = Color3.fromRGB(15, 15, 15)}, container)
	end

	-- resize the whole weapon around its handle
	scale = scale or 1
	if scale ~= 1 then
		local hcf = handle.CFrame
		for _, p in ipairs(container:GetChildren()) do
			if p:IsA("BasePart") and p ~= handle then
				local rel = hcf:ToObjectSpace(p.CFrame)
				p.CFrame = hcf * (CFrame.new(rel.Position * scale) * (rel - rel.Position))
			end
		end
		for _, p in ipairs(container:GetChildren()) do
			if p:IsA("BasePart") then p.Size = p.Size * scale end
		end
		for _, d in ipairs(container:GetDescendants()) do
			if d:IsA("Attachment") then
				d.Position = d.Position * scale
			elseif d:IsA("SpecialMesh") and d.MeshType == Enum.MeshType.FileMesh then
				d.Scale = d.Scale * scale
				d.Offset = d.Offset * scale
			end
		end
	end

	for _, p in ipairs(container:GetChildren()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			if p ~= handle then
				mk("Weld", {Part0 = handle, Part1 = p, C0 = handle.CFrame:ToObjectSpace(p.CFrame)}, p)
			end
		end
	end
	container.PrimaryPart = handle

	-- muzzle: attachment/part named muzzle/fire/barrel, else the tip of the handle
	local muzzleObj
	for _, d in ipairs(container:GetDescendants()) do
		local n = d.Name:lower()
		if (d:IsA("Attachment") or d:IsA("BasePart")) and (n:find("muzzle") or n:find("firepoint") or n:find("barrel")) then
			muzzleObj = d
			break
		end
	end
	local function muzzleCF()
		if muzzleObj then
			return muzzleObj:IsA("Attachment") and muzzleObj.WorldCFrame or muzzleObj.CFrame
		end
		return handle.CFrame * CFrame.new(0, 0, -handle.Size.Z / 2)
	end
	return container, handle, muzzleCF
end

----------------------------------------------------------------
-- officer (R6, self-built, police uniform)
----------------------------------------------------------------
local NAVY = Color3.fromRGB(22, 36, 82)
local PANTS = Color3.fromRGB(16, 20, 38)
local SKIN = Color3.fromRGB(234, 184, 146)

local function buildOfficer(cf, name)
	local m = Instance.new("Model")
	m.Name = name
	m:SetAttribute("Police", true)

	local function part(n, size, color)
		return mk("Part", {Name = n, Size = size, Color = color, TopSurface = Enum.SurfaceType.Smooth,
			BottomSurface = Enum.SurfaceType.Smooth}, m)
	end
	local hrp = part("HumanoidRootPart", Vector3.new(2, 2, 1), NAVY)
	hrp.Transparency = 1
	local torso = part("Torso", Vector3.new(2, 2, 1), NAVY)
	local head = part("Head", Vector3.new(2, 1, 1), SKIN)
	mk("SpecialMesh", {MeshType = Enum.MeshType.Head, Scale = Vector3.new(1.25, 1.25, 1.25)}, head)
	mk("Decal", {Name = "face", Texture = "rbxasset://textures/face.png"}, head)
	local lArm = part("Left Arm", Vector3.new(1, 2, 1), NAVY)
	local rArm = part("Right Arm", Vector3.new(1, 2, 1), NAVY)
	local lLeg = part("Left Leg", Vector3.new(1, 2, 1), PANTS)
	local rLeg = part("Right Leg", Vector3.new(1, 2, 1), PANTS)
	m.PrimaryPart = hrp

	local function motor(n, p0, p1, c0, c1)
		return mk("Motor6D", {Name = n, Part0 = p0, Part1 = p1, C0 = c0, C1 = c1}, p0)
	end
	motor("RootJoint", hrp, torso, CFrame.new(0,0,0,-1,0,0,0,0,1,0,1,0), CFrame.new(0,0,0,-1,0,0,0,0,1,0,1,0))
	motor("Neck", torso, head, CFrame.new(0,1,0,-1,0,0,0,0,1,0,1,0), CFrame.new(0,-0.5,0,-1,0,0,0,0,1,0,1,0))
	local rs = motor("Right Shoulder", torso, rArm, CFrame.new(1,0.5,0,0,0,1,0,1,0,-1,0,0), CFrame.new(-0.5,0.5,0,0,0,1,0,1,0,-1,0,0))
	local ls = motor("Left Shoulder", torso, lArm, CFrame.new(-1,0.5,0,0,0,-1,0,1,0,1,0,0), CFrame.new(0.5,0.5,0,0,0,-1,0,1,0,1,0,0))
	local rh = motor("Right Hip", torso, rLeg, CFrame.new(1,-1,0,0,0,1,0,1,0,-1,0,0), CFrame.new(0.5,1,0,0,0,1,0,1,0,-1,0,0))
	local lh = motor("Left Hip", torso, lLeg, CFrame.new(-1,-1,0,0,0,-1,0,1,0,1,0,0), CFrame.new(-0.5,1,0,0,0,-1,0,1,0,1,0,0))

	local hum = mk("Humanoid", {RigType = Enum.HumanoidRigType.R6, MaxHealth = 150, Health = 150,
		DisplayName = "Officer", WalkSpeed = 16, HipHeight = 0}, m)
	mk("Animator", {}, hum)

	local function acc(n, size, color, parent, offset)
		local p = mk("Part", {Name = n, Size = size, Color = color, CanCollide = false, Massless = true,
			Material = Enum.Material.SmoothPlastic}, m)
		p.CFrame = parent.CFrame * offset
		weld(parent, p)
		return p
	end
	acc("Belt", Vector3.new(2.1, 0.35, 1.1), Color3.fromRGB(10, 10, 10), torso, CFrame.new(0, -0.8, 0))
	acc("BeltBuckle", Vector3.new(0.35, 0.3, 0.1), Color3.fromRGB(200, 170, 60), torso, CFrame.new(0, -0.8, -0.56))
	acc("Badge", Vector3.new(0.4, 0.45, 0.1), Color3.fromRGB(215, 180, 60), torso, CFrame.new(0.55, 0.5, -0.52))
	acc("Radio", Vector3.new(0.35, 0.5, 0.25), Color3.fromRGB(20, 20, 20), torso, CFrame.new(-0.6, 0.55, -0.55))
	acc("Tie", Vector3.new(0.25, 1.1, 0.1), Color3.fromRGB(10, 10, 15), torso, CFrame.new(0, 0.35, -0.52))
	acc("Collar", Vector3.new(1.0, 0.25, 1.05), Color3.fromRGB(235, 235, 235), torso, CFrame.new(0, 0.9, 0))
	acc("LeftBoot", Vector3.new(1.05, 0.5, 1.05), Color3.fromRGB(8, 8, 8), lLeg, CFrame.new(0, -0.75, 0))
	acc("RightBoot", Vector3.new(1.05, 0.5, 1.05), Color3.fromRGB(8, 8, 8), rLeg, CFrame.new(0, -0.75, 0))
	acc("LeftHand", Vector3.new(1.02, 0.5, 1.02), SKIN, lArm, CFrame.new(0, -0.75, 0))
	acc("RightHand", Vector3.new(1.02, 0.5, 1.02), SKIN, rArm, CFrame.new(0, -0.75, 0))
	acc("CapTop", Vector3.new(1.35, 0.5, 1.35), Color3.fromRGB(14, 22, 55), head, CFrame.new(0, 0.75, 0))
	acc("CapBrim", Vector3.new(1.3, 0.1, 0.7), Color3.fromRGB(5, 5, 5), head, CFrame.new(0, 0.6, -0.8))
	acc("CapBadge", Vector3.new(0.3, 0.3, 0.05), Color3.fromRGB(215, 180, 60), head, CFrame.new(0, 0.78, -0.7))

	m.Parent = workspace
	m:PivotTo(cf)
	return m, hum, hrp, rs, ls, rh, lh, rArm, head
end

----------------------------------------------------------------
-- police car: one rigid body driven with forces
-- v17: wheels (car.Wheels.FL/FR/RL/RR) get raycast suspension, steering and spin
----------------------------------------------------------------
local function spawnCar(cf, carId, flipFront)
	local ok, objs = pcall(function() return game:GetObjects("rbxassetid://" .. (carId or CAR_ID)) end)
	if not ok or not objs or not objs[1] then
		warn("Police car failed to load")
		return nil
	end
	local car = objs[1]
	if not car:IsA("Model") then
		local mdl = Instance.new("Model")
		car.Parent = mdl
		car = mdl
	end
	car.Name = "PoliceCar"
	car:SetAttribute("Police", true)
	car.Parent = workspace
	car:PivotTo(cf)

	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("BodyMover") or d:IsA("RocketPropulsion") or (d:IsA("Constraint") and not d:IsA("WeldConstraint")) then
			d:Destroy()
		end
	end

	-- find the wheels: parts/models named FL FR RL RR (inside "Wheels" if it exists), else anything named wheel/tire
	local wheelSet, wheelDefs = {}, {}
	local searchRoot = car
	for _, inst in ipairs(car:GetDescendants()) do
		if inst.Name:lower() == "wheels" and (inst:IsA("Model") or inst:IsA("Folder") or inst:IsA("BasePart")) then
			searchRoot = inst
			break
		end
	end
	local cands, candSet = {}, {}
	for _, n in ipairs({"FL", "FR", "RL", "RR"}) do
		for _, inst in ipairs(searchRoot:GetDescendants()) do
			if (inst:IsA("BasePart") or inst:IsA("Model")) and inst.Name:upper() == n then
				table.insert(cands, inst)
				candSet[inst] = true
				break
			end
		end
	end
	if #cands < 4 then
		cands, candSet = {}, {}
		for _, inst in ipairs(car:GetDescendants()) do
			local nm = inst.Name:lower()
			if (inst:IsA("BasePart") or inst:IsA("Model")) and (nm:find("wheel") or nm:find("tire") or nm:find("tyre"))
				and nm ~= "wheels" and not candSet[inst.Parent] then
				table.insert(cands, inst)
				candSet[inst] = true
			end
		end
	end
	for _, w in ipairs(cands) do
		local parts = {}
		if w:IsA("BasePart") then table.insert(parts, w) end
		for _, dd in ipairs(w:GetDescendants()) do
			if dd:IsA("BasePart") then table.insert(parts, dd) end
		end
		local hub, hv = nil, 0
		for _, p in ipairs(parts) do
			local v = p.Size.X * p.Size.Y * p.Size.Z
			if v > hv then hub, hv = p, v end
		end
		if hub then
			for _, p in ipairs(parts) do wheelSet[p] = true end
			table.insert(wheelDefs, {hub = hub, parts = parts, cs = SUSP_TRAVEL, yaw = 0, spin = 0})
		end
	end
	warn("[PoliceCar] wheels found: " .. #wheelDefs)
	if #wheelDefs == 0 then
		warn("[PoliceCar] no wheels detected. Car contents:")
		for _, inst in ipairs(car:GetDescendants()) do
			if inst:IsA("BasePart") or inst:IsA("Model") or inst:IsA("Folder") then
				warn("  " .. inst:GetFullName() .. " (" .. inst.ClassName .. ")")
			end
		end
	end

	-- bounding box of the car body (no wheels) in a given frame
	local function bounds(frame)
		local mn = Vector3.new(math.huge, math.huge, math.huge)
		local mx = Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, p in ipairs(car:GetDescendants()) do
			if p:IsA("BasePart") and not wheelSet[p] then
				local rel = frame:ToObjectSpace(p.CFrame)
				local hs = p.Size / 2
				for sx = -1, 1, 2 do
					for sy = -1, 1, 2 do
						for sz = -1, 1, 2 do
							local c = rel:PointToWorldSpace(Vector3.new(hs.X * sx, hs.Y * sy, hs.Z * sz))
							mn = Vector3.new(math.min(mn.X, c.X), math.min(mn.Y, c.Y), math.min(mn.Z, c.Z))
							mx = Vector3.new(math.max(mx.X, c.X), math.max(mx.Y, c.Y), math.max(mx.Z, c.Z))
						end
					end
				end
			end
		end
		return mn, mx
	end

	-- P = the car's upright frame (model pivot; flipped 180 if the rig was built upside down)
	local P = car:GetPivot()
	local mn, mx = bounds(P)
	if mn.X == math.huge then
		warn("[PoliceCar] no body parts found")
		car:Destroy()
		return nil
	end
	local flip = CAR_UPSIDE_DOWN
	if flip == nil and #wheelDefs > 0 then
		local cs = Vector3.zero
		for _, w in ipairs(wheelDefs) do cs += P:PointToObjectSpace(w.hub.Position) end
		cs /= #wheelDefs
		local bc, bs = (mn + mx) / 2, mx - mn
		local hz = Vector3.new(cs.X - bc.X, 0, cs.Z - bc.Z).Magnitude
		flip = hz < 0.3 * math.max(bs.X, bs.Z) and cs.Y > bc.Y + 0.1 * bs.Y
		if flip then warn("[PoliceCar] rig is upside down in the model, flipping it upright") end
	end
	if flip then
		P = P * CFrame.Angles(0, 0, math.pi)
		mn, mx = bounds(P)
	end
	local bodyC, bodySz = (mn + mx) / 2, mx - mn

	-- cut the rig's own joints to the wheels (we drive them ourselves)
	for _, dd in ipairs(car:GetDescendants()) do
		if (dd:IsA("JointInstance") or dd:IsA("WeldConstraint")) and (wheelSet[dd.Part0] or wheelSet[dd.Part1]) then
			dd:Destroy()
		end
	end

	local base, bestV = nil, 0
	for _, p in ipairs(car:GetDescendants()) do
		if p:IsA("BasePart") and not wheelSet[p] then
			local v = p.Size.X * p.Size.Y * p.Size.Z
			if v > bestV then base, bestV = p, v end
		end
	end
	if not base then return nil end
	car.PrimaryPart = base
	for _, p in ipairs(car:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.02, 0, 1, 1)
			if wheelSet[p] then
				p.Massless = true
				p.CanCollide = false
			elseif p ~= base then
				weld(base, p)
			end
		end
	end

	-- the rig may ship its wheels away from the body: snap them under the car (keeps their track + wheelbase)
	if #wheelDefs > 0 then
		local cSum, rSum = Vector3.zero, 0
		for _, w in ipairs(wheelDefs) do
			cSum += P:PointToObjectSpace(w.hub.Position)
			local s = {w.hub.Size.X, w.hub.Size.Y, w.hub.Size.Z}
			table.sort(s)
			rSum += s[3] / 2
		end
		local cC, avgR = cSum / #wheelDefs, rSum / #wheelDefs
		local horiz = Vector3.new(cC.X - bodyC.X, 0, cC.Z - bodyC.Z).Magnitude
		local far = horiz > 0.3 * math.max(bodySz.X, bodySz.Z) or cC.Y > mx.Y or cC.Y < mn.Y - bodySz.Y
		warn(string.format("[PoliceCar] wheel cluster offset %.1f studs from body, snapping: %s", horiz, tostring(far)))
		if far then
			local target = Vector3.new(bodyC.X, mn.Y + avgR * WHEEL_RIDE + WHEEL_Y_ADJUST, bodyC.Z)
			local delta = P:VectorToWorldSpace(target - cC)
			for _, w in ipairs(wheelDefs) do
				for _, p in ipairs(w.parts) do p.CFrame = p.CFrame + delta end
			end
		end
	end
	for _, w in ipairs(wheelDefs) do
		for _, p in ipairs(w.parts) do
			if p ~= w.hub then weld(w.hub, p) end
		end
		local s = {w.hub.Size.X, w.hub.Size.Y, w.hub.Size.Z}
		table.sort(s)
		w.radius = s[3] / 2
		w.rest = base.CFrame:ToObjectSpace(w.hub.CFrame)
		w.joint = mk("Weld", {Part0 = base, Part1 = w.hub, C0 = w.rest}, base)
	end

	-- light bar on the roof (in the upright frame, so it works whatever way the base part is rotated)
	local longZ = bodySz.Z >= bodySz.X
	local length = longZ and bodySz.Z or bodySz.X
	local width = longZ and bodySz.X or bodySz.Z
	local bar = {}
	for i, c in ipairs({Color3.fromRGB(255, 0, 0), Color3.fromRGB(0, 80, 255)}) do
		local off = (i == 1 and -1 or 1) * width * 0.18
		local p = mk("Part", {Name = "Light" .. i,
			Size = longZ and Vector3.new(width * 0.35, 0.4, 0.8) or Vector3.new(0.8, 0.4, width * 0.35),
			Color = c, Material = Enum.Material.Neon, CanCollide = false, Massless = true}, car)
		p.CFrame = P * CFrame.new(bodyC.X + (longZ and off or 0), mx.Y + 0.2, bodyC.Z + (longZ and 0 or off))
		weld(base, p)
		mk("PointLight", {Color = c, Range = 18, Brightness = 3}, p)
		bar[i] = p
	end
	task.spawn(function()
		local s = false
		while car.Parent do
			s = not s
			bar[1].Transparency = s and 0 or 0.8
			bar[2].Transparency = s and 0.8 or 0
			task.wait(0.15)
		end
	end)

	-- axes expressed in the base part's local space (the base part may be rotated inside the model)
	local frame = base.CFrame:ToObjectSpace(P)
	local R = frame - frame.Position
	local lenLocal = R:VectorToWorldSpace(longZ and Vector3.new(0, 0, -1) or Vector3.new(1, 0, 0))
	local upLocal = R:VectorToWorldSpace(Vector3.yAxis)
	local rev = (carId == nil or carId == CAR_ID) and CAR_REVERSE_FRONT or false
	if flipFront then rev = not rev end
	if rev then lenLocal = -lenLocal end
	local frontCF = CFrame.lookAt(Vector3.zero, lenLocal, upLocal)
	local left = upLocal:Cross(lenLocal)
	local height = bodySz.Y

	local eng = mk("Sound", {Name = "Engine", SoundId = "rbxassetid://" .. ENGINE_SOUND_ID, Looped = true,
		Volume = 0.4, RollOffMinDistance = 15, RollOffMaxDistance = 220}, base)
	eng:Play()

	local att = mk("Attachment", {}, base)
	local vf = mk("VectorForce", {Attachment0 = att, RelativeTo = Enum.ActuatorRelativeTo.World,
		ApplyAtCenterOfMass = true, Force = Vector3.zero}, base)
	local al = mk("AlignOrientation", {Attachment0 = att, Mode = Enum.OrientationAlignmentMode.OneAttachment,
		RigidityEnabled = false, MaxTorque = 1e9, MaxAngularVelocity = 8, Responsiveness = 25}, base)

	local d = {car = car, base = base, throttle = 0, steer = 0, brake = false, length = length, width = width, left = left}
	local heading = flat(base.CFrame:VectorToWorldSpace(lenLocal))
	local smoothN = Vector3.yAxis
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.FilterDescendantsInstances = {car}
	function d.getHeading() return heading end
	function d.fwd() return flat(base.CFrame:VectorToWorldSpace(lenLocal)) end
	function d.speed() return base.AssemblyLinearVelocity:Dot(d.fwd()) end
	function d.driverCF()
		return base.CFrame * CFrame.new(left * (width * 0.2) + lenLocal * (length * 0.1) + upLocal * DRIVER_UP) * frontCF
	end
	function d.exitPos()
		return base.CFrame:PointToWorldSpace(left * (width / 2 + 3) + upLocal * (height / 2 + 3))
	end

	-- sirens: wail <-> yelp while chasing
	local wail = mk("Sound", {Name = "Wail", SoundId = "rbxassetid://" .. SIREN_WAIL_ID, Looped = true,
		Volume = 0.8, RollOffMinDistance = 25, RollOffMaxDistance = 350}, base)
	local yelp = mk("Sound", {Name = "Yelp", SoundId = "rbxassetid://" .. SIREN_YELP_ID, Looped = true,
		Volume = 0.8, RollOffMinDistance = 25, RollOffMaxDistance = 350}, base)
	d.sirenOn = false
	function d.setSiren(on) d.sirenOn = on end
	task.spawn(function()
		local useYelp = false
		while car.Parent do
			if d.sirenOn then
				local s, o = wail, yelp
				if useYelp then s, o = yelp, wail end
				o:Stop()
				if not s.IsPlaying then s:Play() end
				local t0, dur = tick(), useYelp and SIREN_YELP_TIME or SIREN_WAIL_TIME
				while car.Parent and d.sirenOn and tick() - t0 < dur do task.wait(0.1) end
				useYelp = not useYelp
			else
				wail:Stop()
				yelp:Stop()
				task.wait(0.2)
			end
		end
	end)

	-- suspension: a spring per wheel (raycast), wheels follow the ground, steer and roll
	local leanP, leanR = 0, 0
	local function stepWheels(dt, fSpeed, vel, up)
		local n = #wheelDefs
		if n == 0 then return Vector3.zero end
		local cfB = base.CFrame
		local bUp = cfB:VectorToWorldSpace(upLocal)
		local mass = base.AssemblyMass
		local vUp = vel:Dot(up)
		local total = Vector3.zero
		local sideSum, foreSum = 0, 0
		for _, w in ipairs(wheelDefs) do
			local rp = w.rest.Position
			local origin = cfB:PointToWorldSpace(rp) + bUp * SUSP_TRAVEL
			local rayLen = w.radius + 2 * SUSP_TRAVEL
			local hit = workspace:Raycast(origin, -bUp * rayLen, groundParams)
			local c = 0
			if hit and hit.Instance.CanCollide then
				local mdl = hit.Instance:FindFirstAncestorOfClass("Model")
				if not (mdl and mdl:FindFirstChildOfClass("Humanoid")) then
					c = math.clamp(rayLen - hit.Distance, 0, 2 * SUSP_TRAVEL)
				end
			end
			if c > 0 then
				local fMag = (mass * workspace.Gravity / n) * (c / SUSP_TRAVEL) - (SUSP_DAMP * mass / n) * vUp
				total += up * math.max(fMag, 0)
			end
			w.cs += (c - w.cs) * math.min(1, dt * 20)
			local isFront = rp:Dot(lenLocal) > 0
			local side = rp:Dot(left) > 0 and 1 or -1
			sideSum += w.cs * side
			foreSum += w.cs * (isFront and 1 or -1)
			local steerAng = isFront and (d.steer * MAX_STEER_ANGLE) or 0
			w.yaw += (steerAng - w.yaw) * math.min(1, dt * 10)
			w.spin = (w.spin + fSpeed / w.radius * dt) % (math.pi * 2)
			w.joint.C0 = CFrame.new(rp + upLocal * (w.cs - SUSP_TRAVEL))
				* CFrame.fromAxisAngle(upLocal, w.yaw)
				* CFrame.fromAxisAngle(left, w.spin)
				* (w.rest - w.rest.Position)
		end
		-- body leans with the springs, in corners, and under throttle / braking
		local tRoll = -(sideSum / math.max(n / 2, 1) / width) * 0.5
			- d.steer * math.clamp(fSpeed / MAX_SPEED, -1, 1) * LEAN_CORNER
		local tPitch = (foreSum / math.max(n / 2, 1) / (length * 0.6)) * 0.5
			+ d.throttle * 0.015 - ((d.brake and fSpeed > 5) and 0.04 or 0)
		leanR += (math.clamp(tRoll, -0.15, 0.15) - leanR) * math.min(1, dt * 6)
		leanP += (math.clamp(tPitch, -0.15, 0.15) - leanP) * math.min(1, dt * 6)
		return total
	end

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not car.Parent or not base.Parent then conn:Disconnect() return end
		local vel = base.AssemblyLinearVelocity
		local cfB = base.CFrame
		local fwd = d.fwd()

		-- ground probe: centre + 4 corners -> slope normal and grounded flag
		local reach = height / 2 + 6
		local leftW = flat(cfB:VectorToWorldSpace(left))
		local offs = {Vector3.zero, fwd * length * 0.4, -fwd * length * 0.4, leftW * width * 0.4, -leftW * width * 0.4}
		local nSum, cnt = Vector3.zero, 0
		for _, o in ipairs(offs) do
			local hit = workspace:Raycast(cfB.Position + o, Vector3.new(0, -reach, 0), groundParams)
			if hit and hit.Normal.Y > 0.3 then
				local mdl = hit.Instance:FindFirstAncestorOfClass("Model")
				if not (mdl and mdl:FindFirstChildOfClass("Humanoid")) then
					nSum += hit.Normal
					cnt += 1
				end
			end
		end
		local grounded = cnt > 0
		local nTarget = grounded and (nSum / cnt).Unit or Vector3.yAxis
		smoothN = smoothN:Lerp(nTarget, math.min(1, dt * 6))
		if smoothN.Magnitude < 0.01 then smoothN = Vector3.yAxis end
		smoothN = smoothN.Unit
		local up = smoothN
		local fwdT = fwd - up * fwd:Dot(up)
		fwdT = fwdT.Magnitude > 0.01 and fwdT.Unit or fwd
		local fSpeed = vel:Dot(fwdT)
		local okW, suspF = pcall(stepWheels, dt, fSpeed, vel, up)
		if not okW then
			if not d.warned then d.warned = true warn("[PoliceCar] wheel error: " .. tostring(suspF)) end
			suspF = Vector3.zero
		end

		-- steering (physics-style: needs speed), then tilt the car to follow the ground
		local sf = math.clamp(fSpeed / 15, -1, 1)
		heading = CFrame.Angles(0, d.steer * TURN_RATE * sf * dt, 0):VectorToWorldSpace(heading)
		if heading:Dot(fwd) < 0.5 then heading = fwd end
		local hT = heading - up * heading:Dot(up)
		hT = hT.Magnitude > 0.01 and hT.Unit or fwdT
		al.CFrame = CFrame.lookAt(Vector3.zero, hT, up) * CFrame.Angles(leanP, 0, leanR) * frontCF:Inverse()

		-- thrust along the slope + cancel the downhill pull of gravity so the car can climb and hold
		local mass = base.AssemblyMass
		local f = Vector3.zero
		if grounded then
			local boost = 1 + (1 - up.Y) * CLIMB_BOOST
			if d.throttle > 0 and fSpeed < MAX_SPEED then
				f = fwdT * d.throttle * ACCEL * boost * mass
			elseif d.throttle < 0 and fSpeed > -MAX_SPEED * 0.4 then
				f = fwdT * d.throttle * ACCEL * boost * mass
			end
			local gF = Vector3.new(0, -workspace.Gravity * mass, 0)
			f -= (gF - up * gF:Dot(up)) * 0.95
		end
		vf.Force = f + suspF

		-- tire grip (only on the ground): kill sideways slide, add drag / brakes
		local newV = vel
		if grounded then
			local vT = vel - up * vel:Dot(up)
			local lat = vT - fwdT * fSpeed
			newV = vel - lat * math.min(1, dt * 6)
			if d.brake then
				newV -= fwdT * fSpeed * math.min(1, dt * 3)
			elseif d.throttle == 0 then
				newV -= fwdT * fSpeed * math.min(1, dt * 0.6)
			end
		end
		base.AssemblyLinearVelocity = newV

		-- engine note follows speed
		local sp = math.clamp(math.abs(fSpeed) / MAX_SPEED, 0, 1)
		eng.PlaybackSpeed = 0.6 + sp * 1.2 + math.max(d.throttle, 0) * 0.1
		eng.Volume = 0.35 + sp * 0.5
	end)
	return d
end

----------------------------------------------------------------
-- road detection
----------------------------------------------------------------
local function nameIsRoad(inst)
	local n = inst.Name:lower()
	local pn = inst.Parent and inst.Parent.Name:lower() or ""
	for _, w in ipairs(ROAD_NAMES) do
		if n:find(w, 1, true) or pn:find(w, 1, true) then return true end
	end
	return false
end

local function colorClose(a, b, tol)
	return math.sqrt((a.R - b.R) ^ 2 + (a.G - b.G) ^ 2 + (a.B - b.B) ^ 2) < tol
end

-- is the surface that a downward ray hit a road? (material, name, learned, color, lane paint)
local function surfaceIsRoad(hit, refY)
	local inst = hit.Instance
	if hit.Normal.Y < 0.7 then return false end -- walls, very steep slopes (hills up to ~45 deg are fine)
	if math.abs(hit.Position.Y - refY) > 35 then return false end -- rooftops far above / below our level
	local mat = hit.Material
	if ROAD_MATS[mat] then return true end
	local isTerrain = inst:IsA("Terrain")
	if not isTerrain and nameIsRoad(inst) then return true end
	for _, r in ipairs(learnedRoads) do
		if r.mat == mat and (isTerrain or not r.color or colorClose(inst.Color, r.color, 0.12)) then return true end
	end
	if isTerrain then return false end
	for _, c in ipairs(ROAD_COLORS) do
		if colorClose(inst.Color, c, 0.12) then return true end
	end
	if USE_COLOR_DETECTION and not NOT_ROAD_MATS[mat] then
		local h, sat, v = inst.Color:ToHSV()
		if sat < 0.2 and v < 0.5 then return true end -- dark gray / black asphalt colors
		local thin = math.min(inst.Size.X, inst.Size.Y, inst.Size.Z) < 1
		if thin then
			if sat < 0.15 and v > 0.8 then return true end -- white lane lines
			if h > 0.1 and h < 0.18 and sat > 0.6 and v > 0.6 then return true end -- yellow lines
		end
	end
	return false
end

local ANGLES = {0, 0.2, -0.2, 0.45, -0.45, 0.7, -0.7, 1.05, -1.05, 1.4, -1.4}

----------------------------------------------------------------
-- police AI
----------------------------------------------------------------
----------------------------------------------------------------
-- realistic explosions: flash, fireball, shockwave, ground ring, fire + smoke + sparks + dust,
-- flying debris, scorch mark, camera shake, damage with falloff and physics push
----------------------------------------------------------------
local EXPLOSION_SOUND = "rbxasset://sounds/impact_explosion_03.mp3"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local function isPoliceInst(inst)
	local cur = inst
	while cur and cur ~= workspace do
		if cur:GetAttribute("Police") then return true end
		cur = cur.Parent
	end
	return false
end

local function tween(inst, t, props, style)
	TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function ghost(props)
	props.Anchored = true
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	props.CastShadow = false
	return mk("Part", props, workspace)
end

local function kp(t, v) return NumberSequenceKeypoint.new(t, v) end

local function explode(pos, radius, maxDamage, soundId)
	radius = radius or 24
	maxDamage = maxDamage or 80
	local gHit = workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -(radius + 10), 0))
	local ground = gHit and gHit.Position

	-- anchor that carries the light, sounds and particles
	local anchor = ghost({Name = "Blast", Size = Vector3.one, Transparency = 1, CFrame = CFrame.new(pos)})
	Debris:AddItem(anchor, 10)

	-- blinding flash that fades
	local light = mk("PointLight", {Color = Color3.fromRGB(255, 170, 70), Range = radius * 3.5,
		Brightness = 12, Shadows = false}, anchor)
	tween(light, 0.9, {Brightness = 0})

	-- white-hot core, orange fireball, expanding shockwave
	local core = ghost({Shape = Enum.PartType.Ball, Size = Vector3.one * 2, Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 245, 200), CFrame = CFrame.new(pos)})
	tween(core, 0.25, {Size = Vector3.one * radius * 0.9, Transparency = 1})
	Debris:AddItem(core, 0.4)
	local ball = ghost({Shape = Enum.PartType.Ball, Size = Vector3.one * 3, Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 120, 25), Transparency = 0.15, CFrame = CFrame.new(pos)})
	tween(ball, 0.55, {Size = Vector3.one * radius * 1.7, Transparency = 1})
	Debris:AddItem(ball, 0.7)
	local shock = ghost({Shape = Enum.PartType.Ball, Size = Vector3.one * 4, Material = Enum.Material.ForceField,
		Color = Color3.fromRGB(255, 255, 255), Transparency = 0.5, CFrame = CFrame.new(pos)})
	tween(shock, 0.45, {Size = Vector3.one * radius * 5, Transparency = 1})
	Debris:AddItem(shock, 0.6)

	-- ground dust ring + scorch mark
	if ground then
		local flat0 = CFrame.new(ground + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
		local ring = ghost({Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 4, 4),
			Color = Color3.fromRGB(190, 170, 140), Transparency = 0.55, CFrame = flat0})
		tween(ring, 0.6, {Size = Vector3.new(0.4, radius * 5, radius * 5), Transparency = 1})
		Debris:AddItem(ring, 0.8)
		local scorch = ghost({Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, radius * 1.5, radius * 1.5),
			Color = Color3.fromRGB(15, 15, 15), Material = Enum.Material.Slate, Transparency = 0.3,
			CFrame = CFrame.new(ground + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))})
		tween(scorch, 25, {Transparency = 1}, Enum.EasingStyle.Linear)
		Debris:AddItem(scorch, 26)

		local dustAnchor = ghost({Size = Vector3.one, Transparency = 1, CFrame = CFrame.new(ground + Vector3.new(0, 1, 0))})
		Debris:AddItem(dustAnchor, 8)
		local dust = mk("ParticleEmitter", {Texture = TEX_SMOKE, Rate = 0, Lifetime = NumberRange.new(1.6, 2.8),
			Speed = NumberRange.new(radius * 1.2, radius * 2.4), SpreadAngle = Vector2.new(80, 80), Drag = 3,
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60), Acceleration = Vector3.new(0, 2, 0),
			Size = NumberSequence.new({kp(0, 3), kp(1, radius * 0.9)}),
			Transparency = NumberSequence.new({kp(0, 0.4), kp(1, 1)}),
			Color = ColorSequence.new(Color3.fromRGB(165, 145, 115), Color3.fromRGB(120, 105, 85))}, dustAnchor)
		dust:Emit(45)
	end

	-- fire burst
	local fire = mk("ParticleEmitter", {Texture = TEX_FIRE, Rate = 0, Lifetime = NumberRange.new(0.5, 1.2),
		Speed = NumberRange.new(radius * 0.6, radius * 1.8), SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-150, 150), LightEmission = 1, Drag = 2.5,
		Acceleration = Vector3.new(0, 8, 0),
		Size = NumberSequence.new({kp(0, radius * 0.5), kp(1, radius * 1.3)}),
		Transparency = NumberSequence.new({kp(0, 0), kp(0.6, 0.3), kp(1, 1)}),
		Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 120)),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 100, 20)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 25, 10))})}, anchor)
	fire:Emit(35)

	-- heavy dark smoke cloud + a rising smoke column
	local smokeProps = {Texture = TEX_SMOKE, Rate = 0, Lifetime = NumberRange.new(3.5, 6),
		Speed = NumberRange.new(4, radius * 0.7), SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40), Drag = 1.2,
		Acceleration = Vector3.new(0, 7, 0),
		Size = NumberSequence.new({kp(0, radius * 0.8), kp(1, radius * 3)}),
		Transparency = NumberSequence.new({kp(0, 0.25), kp(0.7, 0.7), kp(1, 1)}),
		Color = ColorSequence.new(Color3.fromRGB(35, 35, 35), Color3.fromRGB(115, 115, 115))}
	local smoke = mk("ParticleEmitter", smokeProps, anchor)
	smoke:Emit(28)
	local col = mk("ParticleEmitter", {Texture = TEX_SMOKE, Rate = 45, Lifetime = NumberRange.new(3, 5),
		Speed = NumberRange.new(radius * 0.5, radius * 0.9), SpreadAngle = Vector2.new(14, 14), Drag = 1,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-30, 30), Acceleration = Vector3.new(0, 6, 0),
		Size = NumberSequence.new({kp(0, radius * 0.6), kp(1, radius * 2.2)}),
		Transparency = NumberSequence.new({kp(0, 0.35), kp(0.7, 0.75), kp(1, 1)}),
		Color = ColorSequence.new(Color3.fromRGB(25, 25, 25), Color3.fromRGB(95, 95, 95))}, anchor)
	task.delay(1.2, function() col.Enabled = false end)

	-- sparks that arc and fall
	local sparks = mk("ParticleEmitter", {Texture = TEX_SPARK, Rate = 0, Lifetime = NumberRange.new(0.7, 1.6),
		Speed = NumberRange.new(radius * 1.5, radius * 4), SpreadAngle = Vector2.new(180, 180), LightEmission = 1,
		Acceleration = Vector3.new(0, -70, 0), Size = NumberSequence.new({kp(0, 0.9), kp(1, 0)}),
		Transparency = NumberSequence.new({kp(0, 0), kp(1, 1)}),
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 90, 20))}, anchor)
	sparks:Emit(45)

	-- flying debris chunks (some burning)
	local chunkColors = {Color3.fromRGB(50, 48, 46), Color3.fromRGB(85, 70, 55), Color3.fromRGB(30, 30, 30)}
	for _ = 1, 16 do
		local sz = math.random(4, 14) / 10
		local chunk = mk("Part", {Size = Vector3.new(sz, sz * math.random(6, 14) / 10, sz * math.random(6, 14) / 10),
			Color = chunkColors[math.random(1, 3)], Material = Enum.Material.Slate, CanQuery = false, CanTouch = false,
			CFrame = CFrame.new(pos + Vector3.new(math.random(-10, 10) / 5, math.random(0, 10) / 5, math.random(-10, 10) / 5))}, workspace)
		local dir = Vector3.new(math.random(-100, 100), math.random(40, 140), math.random(-100, 100)).Unit
		chunk.AssemblyLinearVelocity = dir * math.random(35, 55 + math.floor(radius))
		chunk.AssemblyAngularVelocity = Vector3.new(math.random(-12, 12), math.random(-12, 12), math.random(-12, 12))
		if math.random() < 0.5 then
			mk("Fire", {Size = 3, Heat = 0, Color = Color3.fromRGB(255, 140, 40),
				SecondaryColor = Color3.fromRGB(80, 30, 10)}, chunk)
		end
		Debris:AddItem(chunk, 5)
	end

	-- sound: sharp crack + deep low rumble
	for _, cfg in ipairs({{1, 3}, {0.55, 2}}) do
		local snd = mk("Sound", {SoundId = soundId and ("rbxassetid://" .. soundId) or EXPLOSION_SOUND, Volume = cfg[2],
			PlaybackSpeed = cfg[1] * (0.92 + math.random() * 0.14), RollOffMinDistance = 40,
			RollOffMaxDistance = 900}, anchor)
		snd:Play()
	end

	-- camera shake for you, stronger the closer you are
	local ph = playerChar and playerChar:FindFirstChildOfClass("Humanoid")
	if ph and playerRoot then
		local dd = (playerRoot.Position - pos).Magnitude
		local range = radius * 9
		if dd < range then
			local power = (1 - dd / range) * 1.4
			task.spawn(function()
				local t0 = tick()
				while tick() - t0 < 0.8 do
					local k = (1 - (tick() - t0) / 0.8) * power
					ph.CameraOffset = Vector3.new((math.random() - 0.5) * k, (math.random() - 0.5) * k, (math.random() - 0.5) * k * 0.5)
					RunService.RenderStepped:Wait()
				end
				ph.CameraOffset = Vector3.zero
			end)
		end
	end

	-- damage with falloff + physical push (suspects get hurt, loose parts get thrown)
	local blast = radius * 1.6
	local seen, pushed = {}, {}
	for _, p in ipairs(workspace:GetPartBoundsInRadius(pos, blast)) do
		local model = p:FindFirstAncestorOfClass("Model")
		local hum = model and model:FindFirstChildOfClass("Humanoid")
		if hum then
			if not seen[model] and isSuspect(model) then
				seen[model] = true
				local r = model:FindFirstChild("HumanoidRootPart") or p
				local d = (r.Position - pos).Magnitude
				local fall = math.clamp(1 - d / blast, 0, 1)
				hum:TakeDamage(maxDamage * fall)
				local dir = (r.Position - pos + Vector3.new(0, 2, 0)).Unit
				r.AssemblyLinearVelocity = r.AssemblyLinearVelocity + dir * (80 * fall) + Vector3.new(0, 30 * fall, 0)
				if fall > 0.45 then hum:ChangeState(Enum.HumanoidStateType.FallingDown) end
			end
		elseif not p.Anchored and not isPoliceInst(p) then
			local root = p.AssemblyRootPart
			if root and not pushed[root] then
				pushed[root] = true
				local d = (p.Position - pos).Magnitude
				local fall = math.clamp(1 - d / blast, 0, 1)
				root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + (p.Position - pos).Unit * (70 * fall) + Vector3.new(0, 25 * fall, 0)
			end
		end
	end
end

----------------------------------------------------------------
-- bombs + hitscan helper + global target finder (used by helicopters)
----------------------------------------------------------------
local function dropBomb(from, vel)
	local bomb = mk("Part", {Name = "PoliceBomb", Shape = Enum.PartType.Ball, Size = Vector3.new(1.8, 1.8, 1.8),
		Color = Color3.fromRGB(35, 35, 40), Material = Enum.Material.Metal, CanCollide = true,
		CFrame = CFrame.new(from)}, workspace)
	bomb:SetAttribute("Police", true)
	bomb.AssemblyLinearVelocity = vel
	local blink = mk("PointLight", {Color = Color3.fromRGB(255, 40, 40), Range = 10, Brightness = 3}, bomb)
	mk("ParticleEmitter", {Texture = TEX_SMOKE, Rate = 30, Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(0, 2), Size = NumberSequence.new({kp(0, 1), kp(1, 3)}),
		Transparency = NumberSequence.new({kp(0, 0.5), kp(1, 1)}),
		Color = ColorSequence.new(Color3.fromRGB(90, 90, 90))}, bomb)
	task.spawn(function()
		while bomb.Parent do
			blink.Brightness = (blink.Brightness > 1) and 0 or 3
			task.wait(0.12)
		end
	end)
	local done = false
	local function boom()
		if done then return end
		done = true
		local p = bomb.Position
		bomb:Destroy()
		explode(p, 26, 95)
	end
	bomb.Touched:Connect(function(hit)
		if hit.CanCollide and not isPoliceInst(hit) then boom() end
	end)
	task.delay(12, boom)
end

local function tracerShot(origin, aimPos, ignore, dmgMin, dmgMax, soundId, soundParent)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore
	local dir = (aimPos - origin).Unit
	local hit = workspace:Raycast(origin, dir * 600, rp)
	local endPos = hit and hit.Position or (origin + dir * 600)
	playSound(soundId, soundParent, 1)
	local len = math.max((endPos - origin).Magnitude, 0.5)
	local tracer = mk("Part", {Size = Vector3.new(0.18, 0.18, len), Color = Color3.fromRGB(255, 170, 60),
		Material = Enum.Material.Neon, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		CFrame = CFrame.lookAt(origin, endPos) * CFrame.new(0, 0, -len / 2)}, workspace)
	Debris:AddItem(tracer, 0.07)
	if hit then
		local spark = mk("Part", {Size = Vector3.new(0.5, 0.5, 0.5), Shape = Enum.PartType.Ball, Color = Color3.fromRGB(255, 210, 100),
			Material = Enum.Material.Neon, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
			CFrame = CFrame.new(endPos)}, workspace)
		Debris:AddItem(spark, 0.06)
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		local h = model and model:FindFirstChildOfClass("Humanoid")
		if h and isSuspect(model) then h:TakeDamage(math.random(dmgMin, dmgMax)) end
	end
end

local chaseLock = nil -- the suspect everyone is currently locked onto

local function lockedRoot(m)
	if not (m and m.Parent) then return nil end
	local h = m:FindFirstChildOfClass("Humanoid")
	if not (h and h.Health > 0 and isSuspect(m)) then return nil end
	return m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Torso")
end

local function findGlobalTarget(fromPos)
	-- stay locked on the same suspect, however far away, until they die / leave / are no longer wanted
	local lr = lockedRoot(chaseLock)
	if lr then return lr end
	chaseLock = nil
	local best, bestD = nil, 1e9
	local function consider(model)
		local h = model:FindFirstChildOfClass("Humanoid")
		local tr = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
		if h and h.Health > 0 and tr and isSuspect(model) then
			local dd = (tr.Position - fromPos).Magnitude
			if dd < bestD then best, bestD = tr, dd end
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if (p ~= player or targetMe) and p.Character then consider(p.Character) end
	end
	if chaseNPCs and not targetPlayer then
		for _, h in ipairs(workspace:GetDescendants()) do
			if h:IsA("Humanoid") and h.Parent:IsA("Model") then consider(h.Parent) end
		end
	end
	if best then chaseLock = best.Parent end
	return best
end

----------------------------------------------------------------
-- heat-seeking missiles (fired by helicopters): model 32686992, launch + thruster + explosion sounds
----------------------------------------------------------------
local missileTemplate = nil
local function getMissileTemplate()
	if missileTemplate ~= nil then return missileTemplate or nil end
	local ok, objs = pcall(function() return game:GetObjects("rbxassetid://" .. MISSILE_MODEL) end)
	if ok and objs and objs[1] then
		local src = objs[1]
		local mdl = Instance.new("Model")
		local parts = {}
		if src:IsA("BasePart") then table.insert(parts, src) end
		for _, d in ipairs(src:GetDescendants()) do
			if d:IsA("BasePart") then table.insert(parts, d) end
		end
		for _, p in ipairs(parts) do p.Parent = mdl end
		if not src:IsA("BasePart") then src:Destroy() end
		for _, d in ipairs(mdl:GetDescendants()) do
			if d:IsA("BaseScript") or d:IsA("Sound") or d:IsA("BodyMover") then d:Destroy() end
		end
		local body, bestV = nil, 0
		for _, p in ipairs(mdl:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				local v = p.Size.X * p.Size.Y * p.Size.Z
				if v > bestV then body, bestV = p, v end
			end
		end
		if body then
			mdl.PrimaryPart = body
			missileTemplate = mdl
			return mdl
		end
	end
	warn("Missile model failed to load, using a block missile")
	missileTemplate = false
	return nil
end

local function fireMissile(fromCF, target, heliModel)
	local tpl = getMissileTemplate()
	local m
	if tpl then
		m = tpl:Clone()
	else
		m = Instance.new("Model")
		local p = mk("Part", {Name = "Body", Size = Vector3.new(1, 1, 5), Color = Color3.fromRGB(200, 200, 200),
			Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false}, m)
		m.PrimaryPart = p
	end
	m:SetAttribute("Police", true)
	local body = m.PrimaryPart
	local pos = fromCF.Position
	local dir = fromCF.LookVector
	m.Parent = workspace
	m:PivotTo(CFrame.lookAt(pos, pos + dir) * MISSILE_ROT)

	-- launch whoosh + looping thruster + exhaust trail
	playSound(MISSILE_LAUNCH_SND, body, 1.5)
	local thr = mk("Sound", {SoundId = "rbxassetid://" .. MISSILE_THRUST_SND, Looped = true, Volume = 1,
		RollOffMinDistance = 20, RollOffMaxDistance = 300}, body)
	thr:Play()
	mk("PointLight", {Color = Color3.fromRGB(255, 150, 50), Range = 16, Brightness = 3}, body)
	mk("ParticleEmitter", {Texture = TEX_FIRE, Rate = 80, Lifetime = NumberRange.new(0.2, 0.4),
		Speed = NumberRange.new(0, 3), LightEmission = 1,
		Size = NumberSequence.new({kp(0, 2), kp(1, 0.2)}),
		Transparency = NumberSequence.new({kp(0, 0), kp(1, 1)}),
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 80, 20))}, body)
	mk("ParticleEmitter", {Texture = TEX_SMOKE, Rate = 60, Lifetime = NumberRange.new(1.2, 2),
		Speed = NumberRange.new(0, 2), Size = NumberSequence.new({kp(0, 1.5), kp(1, 5)}),
		Transparency = NumberSequence.new({kp(0, 0.4), kp(1, 1)}),
		Color = ColorSequence.new(Color3.fromRGB(190, 190, 190), Color3.fromRGB(90, 90, 90))}, body)

	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {m, heliModel}
	local born = tick()
	local done = false
	local conn
	local function boom(p)
		if done then return end
		done = true
		if conn then conn:Disconnect() end
		m:Destroy()
		explode(p, 24, 90, MISSILE_EXPLODE_SND)
	end
	conn = RunService.Heartbeat:Connect(function(dt)
		if done then return end
		if not m.Parent then done = true conn:Disconnect() return end
		local age = tick() - born
		if age > MISSILE_LIFETIME then boom(pos) return end
		-- heat seeking: keeps steering at the target's hot spot (with lead), launches straight for 0.4s first
		if age > 0.4 and target and target.Parent then
			local dd = (target.Position - pos).Magnitude
			local lead = target.Position + target.AssemblyLinearVelocity * math.min(dd / MISSILE_SPEED, 1.5)
			local want = lead - pos
			if want.Magnitude > 0.1 then
				local nd = dir:Lerp(want.Unit, math.min(1, MISSILE_TURN * dt))
				if nd.Magnitude > 0.01 then dir = nd.Unit end
			end
		end
		local step = dir * MISSILE_SPEED * dt
		local hit = workspace:Raycast(pos, step + dir * 2, rp)
		if hit and not isPoliceInst(hit.Instance) then boom(hit.Position) return end
		pos += step
		m:PivotTo(CFrame.lookAt(pos, pos + dir) * MISSILE_ROT)
		if target and target.Parent and (target.Position - pos).Magnitude < 7 then boom(pos) end
	end)
end

----------------------------------------------------------------
-- police helicopter (model 6858256343): rigid body flown with forces,
-- orbits and strafes the target, guns + bombing runs + missiles, can be shot down
----------------------------------------------------------------
local heliObjs = {}

local function findHeli(inst)
	local cur = inst
	while cur and cur ~= workspace do
		if cur:GetAttribute("PoliceHeli") then return cur end
		cur = cur.Parent
	end
	return nil
end

local function damageHeli(model, amount)
	local o = heliObjs[model]
	if o and o.alive then o.damage(amount) end
end

local function spawnHelicopter(spawnPos)
	local ok, objs = pcall(function() return game:GetObjects("rbxassetid://" .. HELI_ID) end)
	if not ok or not objs or not objs[1] then
		warn("Helicopter failed to load")
		return nil
	end
	local heli = objs[1]
	if not heli:IsA("Model") then
		local mdl = Instance.new("Model")
		heli.Parent = mdl
		heli = mdl
	end
	heli.Name = "PoliceHelicopter"
	heli:SetAttribute("Police", true)
	heli:SetAttribute("PoliceHeli", true)
	heli.Parent = workspace
	heli:PivotTo(CFrame.new(spawnPos))

	for _, d in ipairs(heli:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("Sound") or d:IsA("BodyMover") or d:IsA("RocketPropulsion") or (d:IsA("Constraint") and not d:IsA("WeldConstraint")) then
			d:Destroy()
		end
	end

	-- spinning parts = anything named rotor / blade / prop
	local rotorSet, rotors = {}, {}
	for _, p in ipairs(heli:GetDescendants()) do
		if p:IsA("BasePart") then
			local n = p.Name:lower()
			if n:find("rotor") or n:find("blade") or n:find("prop") then
				rotorSet[p] = true
				table.insert(rotors, p)
			end
		end
	end
	local base, bestV = nil, 0
	for _, p in ipairs(heli:GetDescendants()) do
		if p:IsA("BasePart") and not rotorSet[p] then
			local v = p.Size.X * p.Size.Y * p.Size.Z
			if v > bestV then base, bestV = p, v end
		end
	end
	if not base then
		heli:Destroy()
		return nil
	end
	heli.PrimaryPart = base
	for _, p in ipairs(heli:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			if p ~= base and not rotorSet[p] then weld(base, p) end
		end
	end
	for _, p in ipairs(heli:GetDescendants()) do
		if p:IsA("BasePart") then p.CanCollide = false end
	end
	local spin = {}
	for _, p in ipairs(rotors) do
		local sz = p.Size
		local axis = (sz.X <= sz.Y and sz.X <= sz.Z) and Vector3.xAxis or ((sz.Y <= sz.Z) and Vector3.yAxis or Vector3.zAxis)
		local w = mk("Weld", {Part0 = base, Part1 = p, C0 = base.CFrame:ToObjectSpace(p.CFrame)}, p)
		p.Massless = true
		p.CanCollide = false
		table.insert(spin, {w = w, c0 = w.C0, axis = axis, ang = 0, speed = p.Name:lower():find("tail") and 45 or 28})
	end

	local lenLocal = base.Size.Z >= base.Size.X and Vector3.new(0, 0, -1) or Vector3.new(1, 0, 0)
	if HELI_REVERSE_FRONT then lenLocal = -lenLocal end
	local frontCF = CFrame.lookAt(Vector3.zero, lenLocal)
	local length = (lenLocal.X ~= 0) and base.Size.X or base.Size.Z
	local gunLocal = lenLocal * (length / 2) + Vector3.new(0, -base.Size.Y / 2, 0)

	local att = mk("Attachment", {}, base)
	local vf = mk("VectorForce", {Attachment0 = att, RelativeTo = Enum.ActuatorRelativeTo.World,
		ApplyAtCenterOfMass = true, Force = Vector3.zero}, base)
	local al = mk("AlignOrientation", {Attachment0 = att, Mode = Enum.OrientationAlignmentMode.OneAttachment,
		RigidityEnabled = false, MaxTorque = 1e9, MaxAngularVelocity = 3, Responsiveness = 8}, base)

	local heliParams = RaycastParams.new()
	heliParams.FilterType = Enum.RaycastFilterType.Exclude
	heliParams.FilterDescendantsInstances = {heli}

	local obj = {alive = true, health = HELI_HEALTH}
	heliObjs[heli] = obj
	activeHelis += 1

	local target = nil
	local tag = mk("BillboardGui", {Size = UDim2.new(0, 260, 0, 40), StudsOffset = Vector3.new(0, 10, 0),
		AlwaysOnTop = true, Adornee = base}, base)
	local tagText = mk("TextLabel", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0),
		Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.3, Text = "POLICE HELI"}, tag)
	local angle = math.random() * math.pi * 2
	local lastFace = flat(base.CFrame:VectorToWorldSpace(lenLocal))
	local runUntil, nextRun = 0, tick() + 8
	local gunCd, bombCd, missileCd = 0, 0, 0
	local home = spawnPos
	local lastCheckPos, stillT = base.Position, 0

	local function crash()
		if not obj.alive then return end
		obj.alive = false
		activeHelis = math.max(0, activeHelis - 1)
		-- shot down: power cut, it tumbles out of the sky on fire, then blows up on impact
		vf:Destroy()
		al:Destroy()
		local parts = {}
		for _, d in ipairs(heli:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = true
				table.insert(parts, d)
			end
		end
		base.AssemblyAngularVelocity = Vector3.new(math.random(-6, 6),
			math.random(8, 14) * (math.random() < 0.5 and -1 or 1), math.random(-6, 6))
		mk("Fire", {Size = 16, Heat = 12, Color = Color3.fromRGB(255, 140, 40),
			SecondaryColor = Color3.fromRGB(120, 30, 10)}, base)
		mk("Smoke", {Size = 12, Opacity = 0.8, RiseVelocity = 10, Color = Color3.fromRGB(30, 30, 30)}, base)

		local landed = false
		local conns = {}
		local function impact()
			if landed then return end
			landed = true
			for _, c in ipairs(conns) do c:Disconnect() end
			local p = base.Position
			explode(p, 34, 100)
			for _, d in ipairs(heli:GetDescendants()) do
				if d:IsA("WeldConstraint") or d:IsA("Weld") then d:Destroy() end
			end
			for _, d in ipairs(parts) do -- the blast scatters the wreck
				if d.Parent then
					local dir = d.Position - p
					dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.yAxis
					d.AssemblyLinearVelocity = dir * math.random(25, 55) + Vector3.new(0, math.random(15, 40), 0)
				end
			end
			Debris:AddItem(heli, 12)
		end
		local t0 = tick()
		for _, d in ipairs(parts) do
			table.insert(conns, d.Touched:Connect(function(hit)
				if tick() - t0 > 0.4 and hit.CanCollide and not isPoliceInst(hit) then impact() end
			end))
		end
		-- a couple of mid-air secondary blasts while it falls
		task.spawn(function()
			for _, delay in ipairs({0.7, 1.6}) do
				task.wait(delay)
				if landed or not base.Parent then return end
				explode(base.Position, 9, 0)
			end
		end)
		-- ground check each frame (some wrecks never "touch" anything) + safety timeout
		task.spawn(function()
			while not landed and base.Parent and tick() - t0 < 15 do
				local hit = workspace:Raycast(base.Position, Vector3.new(0, -(base.Size.Y / 2 + 6), 0), heliParams)
				if hit and not isPoliceInst(hit.Instance) and tick() - t0 > 0.4 then break end
				task.wait()
			end
			impact()
		end)
	end
	function obj.damage(a)
		obj.health -= a
		if obj.health <= 0 then crash() end
	end

	-- flight physics
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not obj.alive or not heli.Parent or not base.Parent then conn:Disconnect() return end
		local pos = base.Position
		local vel = base.AssemblyLinearVelocity
		local mass = base.AssemblyMass
		local attacking = target ~= nil and target.Parent ~= nil
		local ft = attacking and target or ((playerRoot and playerRoot.Parent) and playerRoot or nil)

		for _, r in ipairs(spin) do
			r.ang += dt * r.speed
			r.w.C0 = r.c0 * CFrame.fromAxisAngle(r.axis, r.ang)
		end

		local goal
		if ft then
			local tpos = ft.Position
			if attacking and tick() < runUntil then
				goal = tpos + Vector3.new(0, HELI_ALT * 0.7, 0) -- bombing run: fly right over the target
			else
				angle += dt * 0.5
				goal = tpos + Vector3.new(math.cos(angle) * HELI_RADIUS, HELI_ALT, math.sin(angle) * HELI_RADIUS)
			end
		else
			goal = home + Vector3.new(0, HELI_ALT, 0)
		end
		-- stay well above the ground and climb over buildings
		local gHit = workspace:Raycast(Vector3.new(goal.X, math.max(pos.Y, goal.Y) + 300, goal.Z), Vector3.new(0, -900, 0), heliParams)
		local goalY = goal.Y
		if gHit then goalY = math.max(goalY, gHit.Position.Y + 40) end
		if vel.Magnitude > 5 then
			local ahead = workspace:Raycast(pos, vel.Unit * 70, heliParams)
			if ahead and ahead.Instance.CanCollide and ahead.Normal.Y < 0.7 then
				local mdl = ahead.Instance:FindFirstAncestorOfClass("Model")
				if not (mdl and mdl:FindFirstChildOfClass("Humanoid")) and not isPoliceInst(ahead.Instance) then
					goalY = math.max(goalY, pos.Y + 60)
				end
			end
		end
		goal = Vector3.new(goal.X, goalY, goal.Z)

		local to = goal - pos
		local desVel = to.Magnitude > 1 and to.Unit * math.min(to.Magnitude * 1.2, HELI_SPEED) or Vector3.zero
		local acc = (desVel - vel) * 2.2
		if acc.Magnitude > 45 then acc = acc.Unit * 45 end
		vf.Force = Vector3.new(0, workspace.Gravity, 0) * mass -- hover only; the velocity below does the flying
		base.AssemblyLinearVelocity = vel:Lerp(desVel, math.min(1, dt * 4))

		-- bank into the acceleration, face the target (or the direction of travel)
		local hAcc = Vector3.new(acc.X, 0, acc.Z)
		local up = (Vector3.yAxis + hAcc * 0.012).Unit
		local face = lastFace
		if ft then
			face = flat(ft.Position - pos)
		elseif vel.Magnitude > 6 then
			face = flat(vel)
		end
		lastFace = face
		local fwdTilt = face - up * face:Dot(up)
		al.CFrame = CFrame.lookAt(Vector3.zero, fwdTilt.Unit, up) * frontCF:Inverse()
	end)

	-- decisions: pick a target, fire the guns, fire missiles, drop bombs
	task.spawn(function()
		while obj.alive and heli.Parent do
			target = findGlobalTarget(base.Position)
			local who = (target and target.Parent) and ("HELI -> " .. target.Parent.Name) or "HELI: escorting you (no suspect)"
			local fto = (target and target.Parent) and target or playerRoot
			tagText.Text = string.format("%s | %d studs | %d spd", who,
				fto and (fto.Position - base.Position).Magnitude or 0, base.AssemblyLinearVelocity.Magnitude)
			-- watchdog: if it sits still while far from its goal, say why and un-pin it
			if fto then
				if (base.Position - lastCheckPos).Magnitude < 1 and (fto.Position - base.Position).Magnitude > 60 then
					stillT += 0.2
				else
					stillT = 0
					lastCheckPos = base.Position
				end
				if stillT > 3 then
					stillT = -1e9
					local rootPart = base.AssemblyRootPart
					warn(string.format("[PoliceHeli] not moving - root anchored: %s, mass: %.1f",
						tostring(rootPart and rootPart.Anchored), base.AssemblyMass))
					for _, d in ipairs(heli:GetDescendants()) do
						if d:IsA("BasePart") then
							d.Anchored = false
						elseif d:IsA("BodyMover") or d:IsA("RocketPropulsion") then
							d:Destroy()
						end
					end
				end
			end
			if target and target.Parent then
				local pos = base.Position
				if tick() > nextRun then
					runUntil = tick() + 6
					nextRun = tick() + 15
				end
				local dd = (target.Position - pos).Magnitude
				if dd < 190 and tick() - gunCd > 2.4 then
					gunCd = tick()
					task.spawn(function()
						for _ = 1, 8 do
							local tr = target
							if not obj.alive or not tr or not tr.Parent then break end
							local origin = base.CFrame:PointToWorldSpace(gunLocal)
							local aim = tr.Position + Vector3.new(math.random(-30, 30) / 10, 0, math.random(-30, 30) / 10)
							tracerShot(origin, aim, {heli}, 6, 11, WEAPON_DEFS.mp9.fire, base)
							task.wait(0.07)
						end
					end)
				end
				-- heat-seeking missile salvo
				if dd < MISSILE_RANGE and dd > 40 and tick() - missileCd > MISSILE_COOLDOWN then
					missileCd = tick()
					task.spawn(function()
						for i = 1, MISSILE_SALVO do
							local tr = target
							if not obj.alive or not tr or not tr.Parent then break end
							local side = (i % 2 == 0) and 1 or -1
							local origin = base.Position + base.CFrame.RightVector * side * 5 - Vector3.new(0, base.Size.Y / 2 + 2, 0)
							fireMissile(CFrame.lookAt(origin, tr.Position), tr, heli)
							task.wait(0.5)
						end
					end)
				end
				local h = pos.Y - target.Position.Y
				if h > 15 and tick() - bombCd > 5 then
					local fallT = math.sqrt(2 * h / workspace.Gravity)
					local hv = base.AssemblyLinearVelocity
					local land = Vector3.new(pos.X + hv.X * fallT, 0, pos.Z + hv.Z * fallT)
					local tv = target.AssemblyLinearVelocity
					local pred = Vector3.new(target.Position.X + tv.X * fallT, 0, target.Position.Z + tv.Z * fallT)
					if (land - pred).Magnitude < 16 then
						bombCd = tick()
						dropBomb(pos - Vector3.new(0, base.Size.Y / 2 + 3, 0), hv)
					end
				end
			end
			task.wait(0.2)
		end
	end)
	return obj
end

local function callHelicopter(near, force)
	if activeHelis >= HELI_MAX then return false end
	if not force and tick() - lastHeli < 30 then return false end
	lastHeli = tick()
	local ang = math.random() * math.pi * 2
	local p = Vector3.new(near.X + math.cos(ang) * 250, near.Y + HELI_ALT + 30, near.Z + math.sin(ang) * 250)
	task.spawn(spawnHelicopter, p)
	return true
end

----------------------------------------------------------------
-- SWAT unit: FBI SWAT car drives in, SWAT_COUNT soldiers (FBI rig) pile out and fight on foot
----------------------------------------------------------------
local soldierTemplate = nil -- Model, or false once loading failed
local weaponTemplate = nil

local function getSoldierTemplate()
	if soldierTemplate ~= nil then return soldierTemplate or nil end
	local ok, objs = pcall(function() return game:GetObjects("rbxassetid://" .. SOLDIER_RIG_ID) end)
	if ok and objs then
		for _, o in ipairs(objs) do
			local h = o:IsA("Humanoid") and o or o:FindFirstChildWhichIsA("Humanoid", true)
			if h and h.Parent:IsA("Model") then
				soldierTemplate = h.Parent
				return soldierTemplate
			end
		end
	end
	warn("FBI soldier rig failed to load - SWAT soldiers use the police uniform instead")
	soldierTemplate = false
	return nil
end

local function getWeaponTemplate()
	if not weaponTemplate then
		local def = WEAPON_DEFS.mp9
		weaponTemplate = loadWeapon(def.model, "mp9", def.scale)
	end
	return weaponTemplate
end

local function spawnSoldier(cf, carModel)
	local def = WEAPON_DEFS.mp9
	local m, hum, root, arm
	local tpl = getSoldierTemplate()
	if tpl then
		m = tpl:Clone()
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BaseScript") then d:Destroy() end
		end
		hum = m:FindFirstChildOfClass("Humanoid")
		root = m:FindFirstChild("HumanoidRootPart")
		arm = m:FindFirstChild("Right Arm") or m:FindFirstChild("RightHand")
		if hum and root and arm then
			m.Parent = workspace
			m:PivotTo(cf)
		else
			m:Destroy()
			m = nil
		end
	end
	if not m then -- fallback: uniformed R6 soldier
		local mm, hh, rr, _, _, _, _, ra = buildOfficer(cf, "SwatSoldier")
		m, hum, root, arm = mm, hh, rr, ra
	end
	m.Name = "SwatSoldier"
	m:SetAttribute("Police", true)
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = false end
	end
	hum.MaxHealth = 100
	hum.Health = 100
	hum.WalkSpeed = 22
	hum.PlatformStand = false
	hum.DisplayName = "SWAT"
	local isR6 = hum.RigType == Enum.HumanoidRigType.R6

	-- MP9 in the right hand
	local gun = getWeaponTemplate():Clone()
	gun.Parent = m
	local handle = gun.PrimaryPart
	local grip = isR6 and GRIP_MP9
		or (CFrame.new(0, -0.3 - MP9_FORWARD, 0) * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.Angles(0, math.rad(180), 0))
	gun:PivotTo(arm.CFrame * grip)
	mk("Weld", {Part0 = arm, Part1 = handle, C0 = grip}, handle)

	-- aiming pose: R6 uses the gun-hold animation, R15 just raises the arm
	local animator = hum:FindFirstChildOfClass("Animator") or mk("Animator", {}, hum)
	local reloadT
	if isR6 then
		local a = Instance.new("Animation")
		a.AnimationId = GUN_HOLD_ID
		local gh = animator:LoadAnimation(a)
		gh.Looped = true
		gh.Priority = Enum.AnimationPriority.Action
		gh:Play()
		local b = Instance.new("Animation")
		b.AnimationId = RELOAD_ANIM_ID
		reloadT = animator:LoadAnimation(b)
		reloadT.Priority = Enum.AnimationPriority.Action
	else
		local sh = m:FindFirstChild("RightShoulder", true)
		if sh and sh:IsA("Motor6D") then sh.C0 = sh.C0 * CFrame.Angles(math.rad(90), 0, 0) end
	end
	local hips = {}
	if isR6 then
		for _, n in ipairs({"Right Hip", "Left Hip"}) do
			local mt = m:FindFirstChild(n, true)
			if mt and mt:IsA("Motor6D") then
				hips[#hips + 1] = {mt = mt, c0 = mt.C0, sign = (n == "Right Hip") and 1 or -1}
			end
		end
	end

	local alive = true
	local mag, reloading, cool = def.magSize, false, true
	local aimed, target = false, nil
	local seed = math.random() * 6

	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not alive or not m.Parent then conn:Disconnect() return end
		local speed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
		local sw = math.sin(tick() * 9) * math.clamp(speed / 16, 0, 1) * 0.9
		for _, h in ipairs(hips) do h.mt.C0 = h.c0 * CFrame.Angles(0, 0, sw * h.sign) end
		if aimed and target and target.Parent then
			hum.AutoRotate = false
			root.CFrame = CFrame.lookAt(root.Position, Vector3.new(target.Position.X, root.Position.Y, target.Position.Z))
		else
			hum.AutoRotate = true
		end
	end)
	hum.Died:Connect(function()
		alive = false
		Debris:AddItem(m, 6)
	end)

	task.spawn(function()
		task.wait(math.random() * 0.5)
		while alive and hum.Health > 0 and m.Parent do
			target = findGlobalTarget(root.Position)
			if target and target.Parent then
				local d = (target.Position - root.Position).Magnitude
				if d > 55 then
					aimed = false
					hum:MoveTo(target.Position) -- run them down
				else
					aimed = true
					if d > 20 then
						hum:MoveTo(target.Position)
					else
						hum:Move(root.CFrame.RightVector * math.sin(tick() * 4 + seed), false) -- strafe
					end
					if cool and not reloading then
						if mag <= 0 then
							reloading = true
							if reloadT then reloadT:Play() end
							playSound(def.reload, handle, 1)
							task.wait(def.reloadTime)
							mag = def.magSize
							reloading = false
						else
							cool = false
							for _ = 1, def.burst do
								if mag <= 0 or not alive then break end
								mag -= 1
								local origin = root.CFrame:PointToWorldSpace(Vector3.new(0.8, 1, -3))
								local aim = target.Position + Vector3.new(math.random(-20, 20) / 10, 0.5, math.random(-20, 20) / 10)
								tracerShot(origin, aim, {m, carModel}, 8, 14, def.fire, handle)
								task.wait(def.spacing)
							end
							task.delay(0.6 / AGGRESSION, function() cool = true end)
						end
					end
				end
			else
				aimed = false
			end
			task.wait(0.1)
		end
	end)
	return m
end

-- soldiers pour out of both sides of the car, one every quarter second
local function deploySoldiers(drv)
	local base = drv.base
	for i = 1, SWAT_COUNT do
		if not (drv.car and drv.car.Parent) then break end
		local side = (i % 2 == 0) and 1 or -1
		local leftW = flat(base.CFrame:VectorToWorldSpace(drv.left))
		local pos = base.Position + leftW * side * (drv.width / 2 + 2.5) + drv.fwd() * ((i - 6) * 0.8)
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = {drv.car}
		local hit = workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), rp)
		local at = hit and (hit.Position + Vector3.new(0, 3.5, 0)) or (pos + Vector3.new(0, 1, 0))
		spawnSoldier(CFrame.new(at), drv.car)
		task.wait(0.25)
	end
end

local function findRoadSpawn(near, rmin, rmax)
	local spawnPos, fallback
	for _ = 1, 16 do
		local ang = math.random() * math.pi * 2
		local r = math.random(rmin, rmax)
		local x, z = near.X + math.cos(ang) * r, near.Z + math.sin(ang) * r
		local hit = workspace:Raycast(Vector3.new(x, near.Y + 120, z), Vector3.new(0, -400, 0))
		if hit and hit.Instance.CanCollide then
			if surfaceIsRoad(hit, hit.Position.Y) then
				spawnPos = hit.Position
				break
			end
			fallback = fallback or hit.Position
		end
	end
	return spawnPos or fallback
end

local function callSwat(near, force)
	if activeSwat >= SWAT_MAX then return false end
	if not force and tick() - lastSwat < 60 then return false end
	local p = findRoadSpawn(near, 120, 200)
	if not p then return false end
	lastSwat = tick()
	activeSwat += 1
	task.spawn(function()
		runOfficer(CFrame.lookAt(p + Vector3.new(0, 3, 0), Vector3.new(near.X, p.Y + 3, near.Z)),
			"SwatDriver", {carId = SWAT_CAR_ID, swat = true})
	end)
	return true
end

-- backup: spawn another officer + car 90-150 studs from the chase, preferring a road
local function callReinforcements(near)
	if activeOfficers >= REINFORCE_MAX or tick() - lastBackup < REINFORCE_COOLDOWN then return false end
	lastBackup = tick()
	local spawnPos, fallback
	for _ = 1, 16 do
		local ang = math.random() * math.pi * 2
		local r = math.random(90, 150)
		local x, z = near.X + math.cos(ang) * r, near.Z + math.sin(ang) * r
		local hit = workspace:Raycast(Vector3.new(x, near.Y + 120, z), Vector3.new(0, -400, 0))
		if hit and hit.Instance.CanCollide then
			if surfaceIsRoad(hit, hit.Position.Y) then
				spawnPos = hit.Position
				break
			end
			fallback = fallback or hit.Position
		end
	end
	spawnPos = spawnPos or fallback
	if not spawnPos then return false end
	task.spawn(function()
		runOfficer(CFrame.lookAt(spawnPos + Vector3.new(0, 3, 0), Vector3.new(near.X, spawnPos.Y + 3, near.Z)), "PoliceOfficer")
	end)
	return true
end

function runOfficer(cf, name, opts)
	local m, hum, root, rs, ls, rh, lh, rArm, head = buildOfficer(cf, name)
	activeOfficers += 1
	local drv = spawnCar(cf * CFrame.new(0, 3, 0), opts and opts.carId, opts and opts.swat and SWAT_REVERSE_FRONT)
	if drv then
		m:PivotTo(drv.base.CFrame * CFrame.new(drv.left * (drv.width / 2 + 3) + Vector3.new(0, 4, 0)))
	end

	local animator = hum:FindFirstChildOfClass("Animator")
	local function load(id)
		local a = Instance.new("Animation")
		a.AnimationId = id
		return animator:LoadAnimation(a)
	end
	local gunHold = load(GUN_HOLD_ID); gunHold.Looped = true; gunHold.Priority = Enum.AnimationPriority.Action
	local stab = load(STAB_ID); stab.Priority = Enum.AnimationPriority.Action
	local reloadT = load(RELOAD_ANIM_ID); reloadT.Priority = Enum.AnimationPriority.Action
	local baseC0 = {[rh] = rh.C0, [lh] = lh.C0, [rs] = rs.C0, [ls] = ls.C0}

	local origCollide = {}
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then origCollide[p] = p.CanCollide end
	end
	local function setSolid(on)
		for p, c in pairs(origCollide) do p.CanCollide = on and c or false end
	end

	local reloading, aimed, cool = false, false, true
	local target = nil
	local alive = true
	local inCar = false
	local deployed = false
	local seatWeld = nil
	local home = root.Position
	local strafeT = tick()

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {m}
	if drv then table.insert(ignore, drv.car) end
	rayParams.FilterDescendantsInstances = ignore

	----------------------------------------------------------------
	-- weapons + ammo
	----------------------------------------------------------------
	local weapons = {}
	for key, def in pairs(WEAPON_DEFS) do
		local container, handle, muzzleCF = loadWeapon(def.model, key, def.scale)
		weapons[key] = {key = key, def = def, container = container, handle = handle, muzzleCF = muzzleCF,
			mag = def.magSize, reserve = def.reserveMax}
	end
	local equipped, equipWeld = nil, nil

	-- ammo HUD above head
	local hud = mk("BillboardGui", {Size = UDim2.new(0, 160, 0, 30), StudsOffset = Vector3.new(0, 3.2, 0),
		AlwaysOnTop = true, Adornee = head}, m)
	local hudText = mk("TextLabel", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0),
		Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.4, Text = ""}, hud)
	local radioUntil = 0
	local function refreshHud()
		if tick() < radioUntil then hudText.Text = "10-78 BACKUP CALLED!" return end
		if reloading then hudText.Text = "RELOADING..." return end
		if equipped then
			hudText.Text = string.upper(equipped.key) .. "  " .. equipped.mag .. "/" .. equipped.def.magSize
				.. "  |  " .. equipped.reserve
		else
			hudText.Text = "Officer"
		end
	end

	local function unequip()
		if equipWeld then equipWeld:Destroy() equipWeld = nil end
		if equipped then equipped.container.Parent = nil end
		equipped = nil
		refreshHud()
	end
	local function equip(key)
		local w = weapons[key]
		if not w or equipped == w then return end
		unequip()
		equipped = w
		w.handle.CFrame = rArm.CFrame * w.def.grip
		w.container.Parent = m
		equipWeld = mk("Weld", {Part0 = rArm, Part1 = w.handle, C0 = w.def.grip}, w.handle)
		refreshHud()
	end

	local function totalAmmo(w) return w.mag + w.reserve end
	local function hasAmmo() return totalAmmo(weapons.pistol) > 0 or totalAmmo(weapons.mp9) > 0 end
	local function pickWeapon(d)
		local p, s = weapons.pistol, weapons.mp9
		if d <= 40 and totalAmmo(s) > 0 then return "mp9" end
		if totalAmmo(p) > 0 then return "pistol" end
		if totalAmmo(s) > 0 then return "mp9" end
		return nil
	end
	local function refillAmmo()
		for _, w in pairs(weapons) do w.mag = w.def.magSize w.reserve = w.def.reserveMax end
		refreshHud()
	end

	local function reload(w)
		if reloading or w.mag >= w.def.magSize or w.reserve <= 0 then return end
		reloading = true
		refreshHud()
		reloadT:Play()
		reloadT:AdjustSpeed(1.5)
		playSound(w.def.reload, w.handle, 1)
		task.wait(w.def.reloadTime)
		local amt = math.min(w.def.magSize - w.mag, w.reserve)
		w.mag += amt
		w.reserve -= amt
		reloading = false
		refreshHud()
	end

	----------------------------------------------------------------
	-- targeting + damage
	----------------------------------------------------------------
	local function findTarget()
		local best, bestD = nil, targetPlayer and 1e9 or 800
		local function consider(model)
			local h = model:FindFirstChildOfClass("Humanoid")
			local tr = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
			if h and h.Health > 0 and tr and isSuspect(model) then
				local dd = dist(root, tr)
				if dd < bestD then best, bestD = tr, dd end
			end
		end
		for _, p in ipairs(Players:GetPlayers()) do
			if (p ~= player or targetMe) and p.Character then consider(p.Character) end
		end
		if chaseNPCs then
			for _, h in ipairs(workspace:GetDescendants()) do
				if h:IsA("Humanoid") and h.Parent:IsA("Model") then consider(h.Parent) end
			end
		end
		return best
	end

	local function damageAt(hit, amount)
		local model = hit:FindFirstAncestorOfClass("Model")
		local h = model and model:FindFirstChildOfClass("Humanoid")
		if h and isSuspect(model) then h:TakeDamage(amount) end
	end

	local function fireShot(w, tr, originPos, soundParent)
		local origin = originPos or w.muzzleCF().Position
		local aimPoint = tr.Position + Vector3.new(math.random(-3, 3) / 2, 0.5, math.random(-3, 3) / 2)
		local dir = (aimPoint - origin).Unit
		w.mag -= 1
		refreshHud()
		playSound(w.def.fire, soundParent or w.handle, 1)

		local flash = mk("Part", {Size = Vector3.new(0.3, 0.3, 0.3), Shape = Enum.PartType.Ball,
			Color = Color3.fromRGB(255, 200, 80), Material = Enum.Material.Neon, Anchored = true,
			CanCollide = false, CanQuery = false, CFrame = CFrame.new(origin)}, workspace)
		mk("PointLight", {Color = Color3.fromRGB(255, 190, 80), Range = 10, Brightness = 4}, flash)
		Debris:AddItem(flash, 0.05)

		local b = mk("Part", {Size = Vector3.new(0.15, 0.15, 5), Color = Color3.fromRGB(255, 230, 80),
			Material = Enum.Material.Neon, Anchored = true, CanCollide = false, CanQuery = false,
			CFrame = CFrame.lookAt(origin, origin + dir)}, workspace)
		Debris:AddItem(b, 2)
		task.spawn(function()
			local pos = origin
			for _ = 1, 60 do
				local step = dir * 20
				local hit = workspace:Raycast(pos, step, rayParams)
				if hit then
					damageAt(hit.Instance, math.random(w.def.dmgMin, w.def.dmgMax))
					break
				end
				pos += step
				b.CFrame = CFrame.lookAt(pos, pos + dir)
				task.wait()
			end
			b:Destroy()
		end)
	end

	local function shoot(tr)
		if not cool or reloading then return end
		local key = pickWeapon(dist(root, tr))
		if not key then return end
		equip(key)
		local w = weapons[key]
		if w.mag <= 0 then
			task.spawn(reload, w)
			return
		end
		cool = false
		aimed = true
		gunHold:Play()
		for _ = 1, w.def.burst do
			if w.mag <= 0 or not alive then break end
			fireShot(w, tr)
			if w.def.spacing > 0 then task.wait(w.def.spacing) end
		end
		if w.mag <= 0 then task.spawn(reload, w) end
		task.delay(w.def.rof / AGGRESSION, function() cool = true end)
	end

	local function arrest(tr)
		if not cool then return end
		cool = false
		stab:Play()
		local h = tr.Parent and tr.Parent:FindFirstChildOfClass("Humanoid")
		if h then h:TakeDamage(math.random(25, 40)) end
		tr.AssemblyLinearVelocity = (tr.Position - root.Position).Unit * 40 + Vector3.new(0, 25, 0)
		task.delay(0.6, function() cool = true end)
	end

	-- idle: top up magazines when nothing is happening
	local function idleReload()
		for _, w in pairs(weapons) do
			if w.mag < w.def.magSize and w.reserve > 0 and not reloading then
				equip(w.key)
				reload(w)
			end
		end
	end

	----------------------------------------------------------------
	-- car enter / exit
	----------------------------------------------------------------
	local function enterCar()
		if not drv or inCar then return end
		inCar = true
		aimed = false
		gunHold:Stop()
		unequip()
		refillAmmo() -- restock from the trunk
		setSolid(false)
		hum.PlatformStand = true
		root.CFrame = drv.driverCF()
		seatWeld = weld(drv.base, root)
	end
	local function exitCar()
		if not inCar then return end
		inCar = false
		drv.throttle, drv.steer, drv.brake = 0, 0, true
		if seatWeld then seatWeld:Destroy() seatWeld = nil end
		root.CFrame = CFrame.new(drv.exitPos())
		hum.PlatformStand = false
		setSolid(true)
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		equip("pistol")
		if opts and opts.swat and not deployed then
			deployed = true
			task.spawn(deploySoldiers, drv) -- 12 soldiers come out of the car
		end
	end

	----------------------------------------------------------------
	-- road-following driving brain
	----------------------------------------------------------------
	local function roadAt(pos, y)
		local hit = workspace:Raycast(Vector3.new(pos.X, y + 60, pos.Z), Vector3.new(0, -170, 0), rayParams)
		if not hit then return nil end
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then return nil end
		return surfaceIsRoad(hit, y)
	end

	local function blocked(dir, len)
		local bp = drv.base.Position
		local hit = workspace:Raycast(bp + Vector3.new(0, 3, 0), dir * len, rayParams)
		if not hit then return false end
		if not hit.Instance.CanCollide or hit.Normal.Y > 0.45 then return false end
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		if model and Players:GetPlayerFromCharacter(model) then return false end -- chase targets are not obstacles
		return true
	end

	local planT, planDir, planMode = 0, nil, "direct"
	local freeUntil, recoverPos, recoverUntil = 0, nil, 0

	-- decide which direction to head: stay on road, pick the road branch closest to the goal
	local function plan(goal)
		local bp = drv.base.Position
		local h = drv.getHeading()
		local toGoal = Vector3.new(goal.X - bp.X, 0, goal.Z - bp.Z)
		local goalDir = toGoal.Magnitude > 0.01 and toGoal.Unit or h

		if toGoal.Magnitude < OFFROAD_DIST or tick() < freeUntil then
			return goalDir, "direct"
		end
		if recoverPos and tick() < recoverUntil then
			local r = Vector3.new(recoverPos.X - bp.X, 0, recoverPos.Z - bp.Z)
			if r.Magnitude > 12 then return r.Unit, "recover" end
			recoverPos = nil
		end

		local bestDir, bestScore = nil, -1e9
		for _, a in ipairs(ANGLES) do
			local dir = CFrame.Angles(0, a, 0):VectorToWorldSpace(h)
			if not blocked(dir, 32) then
				local r1 = roadAt(bp + dir * 22, bp.Y)
				if r1 then
					local r0 = roadAt(bp + dir * 11, bp.Y)
					local r2 = roadAt(bp + dir * 42, bp.Y)
					local score = dir:Dot(goalDir) * 2 - math.abs(a) * 0.6 + (r2 and 1.5 or 0) + (r0 and 1 or -2)
					if score > bestScore then bestDir, bestScore = dir, score end
				end
			end
		end
		if bestDir then
			-- stay in the middle of the road: nudge away from the side where the road runs out
			local lft = Vector3.yAxis:Cross(bestDir)
			local onL = roadAt(bp + bestDir * 14 + lft * 7, bp.Y)
			local onR = roadAt(bp + bestDir * 14 - lft * 7, bp.Y)
			if onL and not onR then bestDir = CFrame.Angles(0, 0.12, 0):VectorToWorldSpace(bestDir)
			elseif onR and not onL then bestDir = CFrame.Angles(0, -0.12, 0):VectorToWorldSpace(bestDir) end
			return bestDir, "road"
		end

		-- off the road: look around for the nearest road point (preferring ones toward the goal)
		local bestP, bestG = nil, 1e9
		for _, radius in ipairs({25, 50, 80, 120}) do
			for i = 0, 11 do
				local ang = i * math.pi / 6
				local p = bp + Vector3.new(math.cos(ang), 0, math.sin(ang)) * radius
				if roadAt(p, bp.Y) then
					local g = (p - goal).Magnitude
					if g < bestG then bestP, bestG = p, g end
				end
			end
			if bestP then break end
		end
		if bestP then
			recoverPos, recoverUntil = bestP, tick() + 2.5
			return (Vector3.new(bestP.X - bp.X, 0, bestP.Z - bp.Z)).Unit, "recover"
		end
		-- no roads anywhere nearby: just drive straight at the goal for a while
		freeUntil = tick() + 3
		return goalDir, "direct"
	end

	local stuckT, reverseUntil = 0, 0
	local function driveTo(goal, scale)
		if tick() - planT > 0.15 or not planDir then
			planDir, planMode = plan(goal)
			planT = tick()
		end
		local h = drv.getHeading()
		local dir = planDir
		local ang = math.atan2(h.Z * dir.X - h.X * dir.Z, h:Dot(dir)) -- + = turn left
		local steer = math.clamp(ang * 1.5, -1, 1)
		local throttle = scale
		if math.abs(ang) > 1.2 then throttle = 0.35 * scale
		elseif math.abs(ang) > 0.6 then throttle = 0.7 * scale end

		-- last-second obstacle dodge (any mode)
		if blocked(h, 26) then
			local l = CFrame.Angles(0, 0.7, 0):VectorToWorldSpace(h)
			local r = CFrame.Angles(0, -0.7, 0):VectorToWorldSpace(h)
			if not blocked(l, 26) then steer = 1
			elseif not blocked(r, 26) then steer = -1
			else steer = steer >= 0 and 1 or -1 end
			throttle = math.min(throttle, 0.45)
		end

		local spd = drv.speed()
		if tick() < reverseUntil then
			throttle = -0.8
			steer = -steer
		else
			if math.abs(spd) < 3 and throttle > 0 then stuckT += 0.06 else stuckT = 0 end
			if stuckT > 1.4 then
				reverseUntil = tick() + 1.4
				stuckT = 0
				planDir = nil
				recoverPos = nil
			end
		end
		drv.throttle, drv.steer, drv.brake = throttle, steer, false
	end

	----------------------------------------------------------------
	-- animation / aim loop
	----------------------------------------------------------------
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not alive or not m.Parent then conn:Disconnect() return end
		if inCar then
			for mt, c0 in pairs(baseC0) do mt.C0 = c0 end
			return
		end
		local speed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
		local sw = math.sin(tick() * 9) * math.clamp(speed / 16, 0, 1) * 0.9
		rh.C0 = baseC0[rh] * CFrame.Angles(0, 0, sw)
		lh.C0 = baseC0[lh] * CFrame.Angles(0, 0, -sw)
		if aimed and target and target.Parent then
			rs.C0 = baseC0[rs]; ls.C0 = baseC0[ls]
			hum.AutoRotate = false
			root.CFrame = CFrame.lookAt(root.Position, Vector3.new(target.Position.X, root.Position.Y, target.Position.Z))
			hum:Move(root.CFrame.RightVector * math.sin((tick() - strafeT) * 5), false)
			if math.random(1, 120) == 1 then hum.Jump = true end
		else
			hum.AutoRotate = true
			rs.C0 = baseC0[rs] * CFrame.Angles(0, 0, -sw)
			ls.C0 = baseC0[ls] * CFrame.Angles(0, 0, sw)
		end
	end)

	hum.Died:Connect(function()
		alive = false
		if drv then
			drv.throttle, drv.steer, drv.brake = 0, 0, true
			drv.setSiren(false)
		end
		task.delay(5, function() m:Destroy() end)
		activeOfficers = math.max(0, activeOfficers - 1)
		if opts and opts.swat then activeSwat = math.max(0, activeSwat - 1) end
	end)

	----------------------------------------------------------------
	-- main loop
	----------------------------------------------------------------
	local chaseStart, radioCheck = nil, 0
	local lastRam = 0
	local pitSide = 1
	local lastCarShot, carReloadUntil = 0, 0
	local waypoint = nil
	task.spawn(function()
		enterCar()
		while alive and hum.Health > 0 and m.Parent do
			target = findGlobalTarget(root.Position)
			if drv then drv.setSiren(target ~= nil) end
			if target then
				chaseStart = chaseStart or tick()
				if tick() - chaseStart > HELI_DELAY then callHelicopter(target.Position) end
				if tick() - chaseStart > SWAT_DELAY then callSwat(target.Position) end
				if tick() - radioCheck > 5 then
					radioCheck = tick()
					-- call backup when the chase drags on, the officer is hurt, or the suspect is getting away
					if (tick() - chaseStart > 15 or hum.Health < hum.MaxHealth * 0.6 or dist(root, target) > 150)
						and callReinforcements(target.Position) then
						radioUntil = tick() + 3
						refreshHud()
						task.delay(3, refreshHud)
					end
				end
			else
				chaseStart = nil
			end
			if inCar then
				if target then
					local d = dist(drv.base, target)
					local exitDist = (opts and opts.swat) and 40 or 14
					local spd = drv.speed()
					-- aggressive pursuit: PIT the rear quarter of a moving target, ram one that stands still
					local tv = Vector3.new(target.AssemblyLinearVelocity.X, 0, target.AssemblyLinearVelocity.Z)
					local moving = tv.Magnitude > 8
					local goalPos = target.Position
					local sideVec = Vector3.zero
					if moving then
						local tDir = tv.Unit
						sideVec = Vector3.yAxis:Cross(tDir) * pitSide
						if d > 30 then
							goalPos = target.Position - tDir * 20 + sideVec * 8 -- line up beside the rear
						else
							goalPos = target.Position - tDir * 4 + sideVec * 3 -- aim at the rear quarter
						end
					end
					if d < 11 and math.abs(spd) > 18 and tick() - lastRam > 1.5 then
						lastRam = tick()
						local th = target.Parent:FindFirstChildOfClass("Humanoid")
						if th then th:TakeDamage(20) end
						local root0 = target.AssemblyRootPart or target
						if moving then
							-- PIT: shove the rear sideways so the target spins out
							root0.AssemblyLinearVelocity = root0.AssemblyLinearVelocity - sideVec * 35 + Vector3.new(0, 12, 0)
							root0.AssemblyAngularVelocity = Vector3.new(0, pitSide * 14, 0)
							if th then th:ChangeState(Enum.HumanoidStateType.FallingDown) end
							pitSide = -pitSide
						else
							root0.AssemblyLinearVelocity = drv.fwd() * 60 + Vector3.new(0, 35, 0)
						end
					end

					-- shoot out of the window while driving
					if d < 70 and tick() - lastCarShot > 0.14 and tick() > carReloadUntil then
						local w = (d < 40) and weapons.mp9 or weapons.pistol
						if w.mag <= 0 then w = (w == weapons.mp9) and weapons.pistol or weapons.mp9 end
						if w.mag > 0 then
							lastCarShot = tick() + (w == weapons.pistol and 0.3 or 0)
							local origin = drv.base.CFrame:PointToWorldSpace(drv.left * (drv.width / 2) + Vector3.new(0, 1, 0))
							fireShot(w, target, origin, drv.base)
						else
							-- both empty: quick reload from the trunk
							carReloadUntil = tick() + 2
							for _, ww in pairs(weapons) do
								local amt = math.min(ww.def.magSize - ww.mag, ww.reserve)
								ww.mag += amt
								ww.reserve -= amt
							end
						end
					end
					if d < exitDist and math.abs(spd) < 12 then
						exitCar()
					else
						driveTo(goalPos, 1)
						if (d < 18 and spd > 35) or (opts and opts.swat and d < 55 and spd > 8) then drv.throttle = 0 drv.brake = true end
					end
				else
					if not waypoint or (drv.base.Position - waypoint).Magnitude < 25 then
						waypoint = home + Vector3.new(math.random(-300, 300), 0, math.random(-300, 300))
					end
					driveTo(waypoint, 0.5)
				end
			else
				if target then
					local d = dist(root, target)
					if drv and d > 45 and dist(root, drv.base) < 200 then
						aimed = false
						gunHold:Stop()
						hum:MoveTo(drv.base.Position)
						if dist(root, drv.base) < 10 then enterCar() end
					elseif d > 90 then
						aimed = false
						gunHold:Stop()
						hum:MoveTo(target.Position)
					elseif d > 18 and hasAmmo() then
						shoot(target)
					else
						aimed = false
						gunHold:Stop()
						hum:MoveTo(target.Position)
						task.wait(0.25)
						if target.Parent and dist(root, target) < 10 then arrest(target) end
					end
				else
					aimed = false
					gunHold:Stop()
					idleReload()
					if drv and dist(root, drv.base) < 200 then
						hum:MoveTo(drv.base.Position)
						if dist(root, drv.base) < 10 then enterCar() end
					else
						hum:MoveTo(home + Vector3.new(math.random(-40, 40), 0, math.random(-40, 40)))
					end
				end
			end
			task.wait(0.06)
		end
	end)
	return m
end

----------------------------------------------------------------
-- spawn + GUI
----------------------------------------------------------------
local function callPolice()
	local base = playerRoot.CFrame * CFrame.new(0, 0, -40)
	runOfficer(CFrame.lookAt(base.Position, playerRoot.Position), "PoliceOfficer")
end

local gui = mk("ScreenGui", {Name = "PoliceAIGui", ResetOnSpawn = false}, player:WaitForChild("PlayerGui"))
local frame = mk("Frame", {Position = UDim2.new(0.02, 0, 0.08, 0), Size = UDim2.new(0, 150, 0, 340),
	BackgroundColor3 = NAVY, Active = true, Draggable = true}, gui)
mk("UICorner", {}, frame)
mk("TextLabel", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), Font = Enum.Font.GothamBold,
	Text = "POLICE AI", TextColor3 = Color3.new(1, 1, 1), TextSize = 16}, frame)
local npcBtn = mk("TextButton", {Position = UDim2.new(0.07, 0, 0, 66), Size = UDim2.new(0.86, 0, 0, 34),
	BackgroundColor3 = Color3.fromRGB(60, 120, 60), Font = Enum.Font.GothamBold, Text = "Chase NPCs: OFF",
	TextColor3 = Color3.new(1, 1, 1), TextSize = 13}, frame)
mk("UICorner", {}, npcBtn)
local backupBtn = mk("TextButton", {Position = UDim2.new(0.07, 0, 0, 104), Size = UDim2.new(0.86, 0, 0, 34),
	BackgroundColor3 = Color3.fromRGB(160, 40, 40), Font = Enum.Font.GothamBold, Text = "Call Backup",
	TextColor3 = Color3.new(1, 1, 1), TextSize = 14}, frame)
mk("UICorner", {}, backupBtn)

-- target picker: tap to cycle Any -> each other player -> Any
local targetBtn = mk("TextButton", {Position = UDim2.new(0.07, 0, 0, 28), Size = UDim2.new(0.86, 0, 0, 34),
	BackgroundColor3 = Color3.fromRGB(40, 70, 150), Font = Enum.Font.GothamBold, Text = "Target: Any",
	TextColor3 = Color3.new(1, 1, 1), TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd}, frame)
mk("UICorner", {}, targetBtn)
local function setTarget(p)
	targetPlayer = p
	targetBtn.Text = p and ("Target: " .. p.DisplayName) or "Target: Any"
	targetBtn.BackgroundColor3 = p and Color3.fromRGB(170, 50, 50) or Color3.fromRGB(40, 70, 150)
end
targetBtn.MouseButton1Click:Connect(function()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then table.insert(list, p) end -- you can never be picked
	end
	local idx = table.find(list, targetPlayer)
	if not idx then setTarget(list[1])
	elseif list[idx + 1] then setTarget(list[idx + 1])
	else setTarget(nil) end
end)
Players.PlayerRemoving:Connect(function(p)
	if p == targetPlayer then setTarget(nil) end
end)

npcBtn.MouseButton1Click:Connect(function()
	chaseNPCs = not chaseNPCs
	npcBtn.Text = chaseNPCs and "Chase NPCs: ON" or "Chase NPCs: OFF"
	npcBtn.BackgroundColor3 = chaseNPCs and Color3.fromRGB(170, 50, 50) or Color3.fromRGB(60, 120, 60)
end)
backupBtn.MouseButton1Click:Connect(callPolice)

-- stand on a road and tap: that surface (material + color) counts as road from now on
local learnBtn = mk("TextButton", {Position = UDim2.new(0.07, 0, 0, 142), Size = UDim2.new(0.86, 0, 0, 34),
	BackgroundColor3 = Color3.fromRGB(90, 90, 90), Font = Enum.Font.GothamBold, Text = "Learn Road Here",
	TextColor3 = Color3.new(1, 1, 1), TextSize = 13}, frame)
mk("UICorner", {}, learnBtn)
learnBtn.MouseButton1Click:Connect(function()
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {playerChar}
	local hit = workspace:Raycast(playerRoot.Position, Vector3.new(0, -12, 0), rp)
	if hit then
		local isT = hit.Instance:IsA("Terrain")
		table.insert(learnedRoads, {mat = hit.Material, color = (not isT) and hit.Instance.Color or nil})
		learnBtn.Text = "Learned! (" .. #learnedRoads .. ")"
	else
		learnBtn.Text = "No ground found"
	end
	task.delay(1.5, function() learnBtn.Text = "Learn Road Here" end)
end)

player.CharacterAdded:Connect(function(c)
	playerChar = c
	playerRoot = c:WaitForChild("HumanoidRootPart")
end)

callPolice()
----------------------------------------------------------------
-- Target Me + Give Weapons buttons
----------------------------------------------------------------
local targetMeBtn = mk("TextButton", {Position = UDim2.new(0.07, 0, 0, 180), Size = UDim2.new(0.86, 0, 0, 34),
	BackgroundColor3 = Color3.fromRGB(60, 120, 60), Font = Enum.Font.GothamBold, Text = "Target Me: OFF",
	TextColor3 = Color3.new(1, 1, 1), TextSize = 13}, frame)
mk("UICorner", {}, targetMeBtn)
targetMeBtn.MouseButton1Click:Connect(function()
	targetMe = not targetMe
	targetMeBtn.Text = targetMe and "Target Me: ON" or "Target Me: OFF"
	targetMeBtn.BackgroundColor3 = targetMe and Color3.fromRGB(170, 50, 50) or Color3.fromRGB(60, 120, 60)
end)

----------------------------------------------------------------
-- YOUR weapons: the police pistol + MP9 as Tools in your backpack
-- (tap to shoot, hold to spray the MP9, RELOAD button, ammo counter, same sounds)
----------------------------------------------------------------
local TOOL_GRIPS = {pistol = CFrame.new(), mp9 = CFrame.new(0, 0, -MP9_FORWARD) * CFrame.Angles(0, math.rad(180), 0)} -- mp9 flipped like the officer's, pushed forward
local AUTO_DELAY = {pistol = 0.3, mp9 = 0.09}

local hudGui = mk("ScreenGui", {Name = "PoliceWeaponHud", ResetOnSpawn = false}, player:WaitForChild("PlayerGui"))
local ammoLabel = mk("TextLabel", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.95, 0),
	Size = UDim2.new(0, 230, 0, 32), BackgroundColor3 = NAVY, BackgroundTransparency = 0.3,
	Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Color3.new(1, 1, 1), Text = "", Visible = false}, hudGui)
mk("UICorner", {}, ammoLabel)
local reloadBtn = mk("TextButton", {AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(0.97, 0, 0.72, 0),
	Size = UDim2.new(0, 95, 0, 46), BackgroundColor3 = Color3.fromRGB(160, 40, 40), Font = Enum.Font.GothamBold,
	Text = "RELOAD", TextSize = 15, TextColor3 = Color3.new(1, 1, 1), Visible = false}, hudGui)
mk("UICorner", {}, reloadBtn)

local current = nil -- state of the weapon you are holding
local playerTools = {}

local function updateHud()
	if not current then
		ammoLabel.Visible = false
		reloadBtn.Visible = false
		return
	end
	ammoLabel.Visible = true
	reloadBtn.Visible = true
	ammoLabel.Text = current.reloading and "RELOADING..."
		or (string.upper(current.key) .. "   " .. current.mag .. "/" .. current.def.magSize .. "  |  " .. current.reserve)
end

local function playerReload(st)
	if st.reloading or st.mag >= st.def.magSize or st.reserve <= 0 then return end
	st.reloading = true
	updateHud()
	playSound(st.def.reload, st.handle, 1)
	task.wait(st.def.reloadTime)
	local amt = math.min(st.def.magSize - st.mag, st.reserve)
	st.mag += amt
	st.reserve -= amt
	st.reloading = false
	updateHud()
end

local function playerFire(st)
	local cam = workspace.CurrentCamera
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {playerChar}
	-- aim where the crosshair (screen centre) points
	local camHit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 1000, rp)
	local aimPoint = camHit and camHit.Position or (cam.CFrame.Position + cam.CFrame.LookVector * 1000)
	local origin = st.muzzleCF().Position
	local dir = (aimPoint - origin).Unit
	local hit = workspace:Raycast(origin, dir * 1000, rp)
	local endPos = hit and hit.Position or (origin + dir * 1000)

	st.mag -= 1
	playSound(st.def.fire, st.handle, 1)

	local len = math.max((endPos - origin).Magnitude, 0.5)
	local tracer = mk("Part", {Size = Vector3.new(0.12, 0.12, len), Color = Color3.fromRGB(255, 230, 80),
		Material = Enum.Material.Neon, Anchored = true, CanCollide = false, CanQuery = false,
		CFrame = CFrame.lookAt(origin, endPos) * CFrame.new(0, 0, -len / 2)}, workspace)
	Debris:AddItem(tracer, 0.06)
	local flash = mk("Part", {Size = Vector3.new(0.3, 0.3, 0.3), Shape = Enum.PartType.Ball,
		Color = Color3.fromRGB(255, 200, 80), Material = Enum.Material.Neon, Anchored = true,
		CanCollide = false, CanQuery = false, CFrame = CFrame.new(origin)}, workspace)
	mk("PointLight", {Color = Color3.fromRGB(255, 190, 80), Range = 10, Brightness = 4}, flash)
	Debris:AddItem(flash, 0.05)

	if hit then
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		local h = model and model:FindFirstChildOfClass("Humanoid")
		if h then h:TakeDamage(math.random(st.def.dmgMin, st.def.dmgMax)) end
		local hm = findHeli(hit.Instance)
		if hm then damageHeli(hm, math.random(st.def.dmgMin, st.def.dmgMax)) end
	end
	updateHud()
end

local function makePlayerTool(key)
	local def = WEAPON_DEFS[key]
	local container, handle, muzzleCF = loadWeapon(def.model, key, def.scale)
	handle.Name = "Handle"
	local tool = Instance.new("Tool")
	tool.Name = key == "mp9" and "MP9" or "Pistol"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.Grip = TOOL_GRIPS[key]
	for _, o in ipairs(container:GetChildren()) do o.Parent = tool end
	container:Destroy()

	local st = {key = key, def = def, tool = tool, handle = handle, muzzleCF = muzzleCF,
		mag = def.magSize, reserve = def.reserveMax, reloading = false, firing = false, last = 0}

	tool.Equipped:Connect(function()
		current = st
		updateHud()
	end)
	tool.Unequipped:Connect(function()
		st.firing = false
		if current == st then current = nil end
		updateHud()
	end)
	tool.Activated:Connect(function()
		st.firing = true
		task.spawn(function()
			while st.firing and current == st do
				if st.reloading then break end
				if st.mag <= 0 then
					task.spawn(playerReload, st) -- empty: reload automatically
					break
				end
				if tick() - st.last >= AUTO_DELAY[key] then
					st.last = tick()
					playerFire(st)
				end
				if key ~= "mp9" then break end -- pistol: one shot per tap
				task.wait(AUTO_DELAY[key])
			end
		end)
	end)
	tool.Deactivated:Connect(function() st.firing = false end)
	return st
end

local function givePlayerWeapons()
	for _, st in ipairs(playerTools) do
		if current == st then current = nil end
		st.tool:Destroy()
	end
	playerTools = {}
	updateHud()
	local bp = player:WaitForChild("Backpack")
	for _, key in ipairs({"pistol", "mp9"}) do
		local st = makePlayerTool(key)
		st.tool.Parent = bp
		table.insert(playerTools, st)
	end
end

reloadBtn.MouseButton1Click:Connect(function()
	if current then task.spawn(playerReload, current) end
end)

local giveBtn = mk("TextButton", {Position = UDim2.new(0.07, 0, 0, 218), Size = UDim2.new(0.86, 0, 0, 34),
	BackgroundColor3 = Color3.fromRGB(40, 100, 140), Font = Enum.Font.GothamBold, Text = "Give Weapons",
	TextColor3 = Color3.new(1, 1, 1), TextSize = 13}, frame)
mk("UICorner", {}, giveBtn)
giveBtn.MouseButton1Click:Connect(givePlayerWeapons)

local heliBtn = mk("TextButton", {Position = UDim2.new(0.07, 0, 0, 256), Size = UDim2.new(0.86, 0, 0, 34),
	BackgroundColor3 = Color3.fromRGB(110, 60, 140), Font = Enum.Font.GothamBold, Text = "Call Heli",
	TextColor3 = Color3.new(1, 1, 1), TextSize = 13}, frame)
mk("UICorner", {}, heliBtn)
heliBtn.MouseButton1Click:Connect(function() callHelicopter(playerRoot.Position, true) end)

local swatBtn = mk("TextButton", {Position = UDim2.new(0.07, 0, 0, 294), Size = UDim2.new(0.86, 0, 0, 34),
	BackgroundColor3 = Color3.fromRGB(20, 20, 20), Font = Enum.Font.GothamBold, Text = "Call SWAT",
	TextColor3 = Color3.new(1, 1, 1), TextSize = 13}, frame)
mk("UICorner", {}, swatBtn)
swatBtn.MouseButton1Click:Connect(function() callSwat(playerRoot.Position, true) end)

player.CharacterAdded:Connect(function()
	task.wait(1)
	givePlayerWeapons() -- backpack is wiped on respawn
end)
givePlayerWeapons()

print("Police AI v17 loaded")
