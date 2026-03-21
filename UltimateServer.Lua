local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local CONFIG = {
	CHECK_INTERVAL = 0.5,
	
	MAX_SPEED = 32,       -- default WalkSpeed is 16; give 2x headroom
	SPEED_STRIKES = 3,        -- strikes before action

	MAX_TELEPORT_DIST = 60,       -- adjust for fast vehicles / abilities
	TELEPORT_STRIKES = 2,

	MAX_AIR_TIME = 5,        -- seconds
	FLY_STRIKES = 3,
	GROUND_RAY_LENGTH = 5,        -- studs below HRP to check for ground

	MAX_JUMPS_PER_WINDOW = 3,
	JUMP_WINDOW = 2,       -- seconds

	MAX_UP_VELOCITY = 80,      -- studs/s upward (generous for jumps)
	GRAVITY_STRIKES = 3,

	ACTION = "kick",

	LOG = false,
}


local playerData = {}   

local function initPlayer(player)
	playerData[player] = {
		lastPos = nil,
		lastCheckTime = tick(),
		airTime = 0,
		speedStrikes = 0,
		teleportStrikes = 0,
		flyStrikes = 0,
		gravityStrikes = 0,
		jumpTimes = {},   
	}
end

local function cleanPlayer(player)
	playerData[player] = nil
end
local function log(msg)
	if CONFIG.LOG then
		print("[AntiCheat] " .. msg)
	end
end

local function punish(player, reason)
	log(("Action: %s | Player: %s | Reason: %s"):format(
		CONFIG.ACTION, player.Name, reason))
	if CONFIG.ACTION == "kick" then
		player:Kick("You were removed: " .. reason)
	elseif CONFIG.ACTION == "warn" then
		warn(("[Ult] WARNING issued to %s: %s"):format(player.Name, reason))
	end
end

local function isOnGround(hrp)
	local ray = RaycastParams.new()
	ray.FilterDescendantsInstances = {hrp.Parent}
	ray.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(
		hrp.Position,
		Vector3.new(0, -CONFIG.GROUND_RAY_LENGTH, 0),
		ray
	)
	return result ~= nil
end


local function checkPlayer(player, dt)
	local data = playerData[player]
	if not data then return end

	local char = player.Character
	if not char then return end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end
	if hum.Health <= 0 then return end   -- skip dead players

	local pos = hrp.Position
	local vel = hrp.AssemblyLinearVelocity

	if data.lastPos then
		local dist   = (pos - data.lastPos).Magnitude
		local speed  = dist / dt

		if speed > CONFIG.MAX_SPEED then
			data.speedStrikes += 1
			log(("SpeedHack? %s | speed=%.1f studs/s | strike %d"):format(
				player.Name, speed, data.speedStrikes))
			if data.speedStrikes >= CONFIG.SPEED_STRIKES then
				punish(player, "WSD")
				return
			end
		else
			data.speedStrikes = math.max(0, data.speedStrikes - 1)
		end

		
		if dist > CONFIG.MAX_TELEPORT_DIST then
			data.teleportStrikes += 1
			log(("TeleportHack? %s | dist=%.1f studs | strike %d"):format(
				player.Name, dist, data.teleportStrikes))
			if data.teleportStrikes >= CONFIG.TELEPORT_STRIKES then
				punish(player, "PCD")
				return
			end
		else
			data.teleportStrikes = math.max(0, data.teleportStrikes - 1)
		end
	end

	if isOnGround(hrp) then
		data.airTime = 0
		data.flyStrikes = math.max(0, data.flyStrikes - 1)
	else
		data.airTime += dt
		if data.airTime > CONFIG.MAX_AIR_TIME then
			data.flyStrikes += 1
			log(("FlyHack? %s | airTime=%.1f s | strike %d"):format(
				player.Name, data.airTime, data.flyStrikes))
			if data.flyStrikes >= CONFIG.FLY_STRIKES then
				punish(player, "FED")
				return
			end
		end
	end


	if vel.Y > CONFIG.MAX_UP_VELOCITY then
		data.gravityStrikes += 1
		log(("GravityHack? %s | upVel=%.1f | strike %d"):format(
			player.Name, vel.Y, data.gravityStrikes))
		if data.gravityStrikes >= CONFIG.GRAVITY_STRIKES then
			punish(player, "BVOLD")
			return
		end
	else
		data.gravityStrikes = math.max(0, data.gravityStrikes - 1)
	end

	local now = tick()
	local recentJumps = {}
	for _, t in ipairs(data.jumpTimes) do
		if now - t <= CONFIG.JUMP_WINDOW then
			table.insert(recentJumps, t)
		end
	end
	data.jumpTimes = recentJumps

	if #recentJumps > CONFIG.MAX_JUMPS_PER_WINDOW then
		log(("InfiniteJump? %s | %d jumps in %.1f s"):format(
			player.Name, #recentJumps, CONFIG.JUMP_WINDOW))
		punish(player, "InfJD")
		-- clear so we don't spam punishments
		data.jumpTimes = {}
		return
	end

	data.lastPos = pos
end

local function onCharacterAdded(player)
	local char = player.Character or player.CharacterAdded:Wait()
	local hum  = char:WaitForChild("Humanoid", 10)
	if not hum then return end

	hum.Jumping:Connect(function(isJumping)
		if not isJumping then return end
		local data = playerData[player]
		if data then
			table.insert(data.jumpTimes, tick())
		end
	end)
end

local function onPlayerAdded(player)
	initPlayer(player)

	player.CharacterAdded:Connect(function()
		local data = playerData[player]
		if data then
			data.lastPos    = nil
			data.airTime    = 0
			data.jumpTimes  = {}
		end
		onCharacterAdded(player)
	end)

	if player.Character then
		onCharacterAdded(player)
	end
end

local function onPlayerRemoving(player)
	cleanPlayer(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

local accumulator = 0

RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < CONFIG.CHECK_INTERVAL then return end

	local elapsed = accumulator
	accumulator   = 0

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(checkPlayer, player, elapsed)
	end
end)

