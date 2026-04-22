local m = {}

--[[

primary file for LOS

]]--

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local AssetService : AssetService = game:GetService("AssetService")

local BASE_MESH = script:WaitForChild("Viewshape"):WaitForChild("BaseMesh")

local focusEditableMesh : EditableMesh = AssetService:CreateEditableMesh()
local focusDynamicMesh = BASE_MESH:Clone()
focusDynamicMesh.Name = "DYNAMIC_LOS_MESH"
focusDynamicMesh.Parent = workspace
focusDynamicMesh.Massless = true




--turn on or off functions
m.EnableLOS = nil

--AddLOSPart
--add a part to the LOS system, places value objects into the instance
m.AddLOSPart = nil

--ModifyLOSPart
m.ModifyLOSPart = nil

--SetLOSFocus
--only one LOS part will render at once, choose which one will activate
--nil will deactivate LOS, but place an barrier blocking view
m.SetLOSFocus = nil

--update
--called every frame
m.update = nil

--createValue
--helper function, convert normal datatypes to instance objects
local createValue = nil

--getValue
--helper function, grab data from value objects
local getValue = nil

--imports
local Viewshape = require(script.Viewshape)
local Line = require(script.Line)
local Crosshair = require(script.Parent.Crosshair)
local HideModels = require(script.HideModels)

local TagService = game:GetService("CollectionService")

--globals
local enabled = true
local wallsFolder = workspace.Walls

--** IMPLEMENTATION **--

type LOSInfo = {
	m_Enabled : boolean,

	--size of the view
	m_ViewRange : number,
	m_ViewAngle : number,
	m_PeripheralRange : number,

	--aiming the view, pick one but rotation dependent will take precedence if both are filled
	m_RotationDependent : boolean,
	m_FixedAngle : number,

	--display info
	m_ViewColor : Color3,
	m_ViewHeight : number,
	m_PreciseMethod : boolean,
	m_RenderInsideOut : boolean
}
--all this function does is add information to the part
function m.AddLOSPart(part: BasePart, info: LOSInfo)
	TagService:AddTag(part, "LOSEmitter")
	for name, value in pairs(info) do
		createValue(name, value, part)
	end

end

function m.SetLOSFocus(part: BasePart)
	--check if the part has information set
	if TagService:HasTag(part, "LOSEmitter") then
		m.LOSFocus = part
	else
		warn(part.." was not initialized as a LOS Part before being set as focus")
	end

end

--local actors = {}
--local actorsFolder = script.Actors
--actorsFolder.Parent = workspace
--local updateActor = script.UpdateActor

local meshCount = 0
local meshDictionary = {}
local viewshapeDictionary = {}
local hiddenDictionary = {}

local function buildActorAndMesh(part)
	if meshCount >= 7 then error("what the flip roblox") end
	local editableMesh : EditableMesh = AssetService:CreateEditableMesh()
	assert(editableMesh, "Editable mesh failed to build")

	local dynamicMesh = BASE_MESH:Clone()
	dynamicMesh.Parent = workspace
	dynamicMesh.Name = "PARTIAL_LOS_MESH"
	dynamicMesh.Massless = true
	dynamicMesh.Color = Color3.new(1, 1, 1)
	dynamicMesh.Material = Enum.Material.Plastic
	dynamicMesh.Transparency = 0.97

	meshCount += 1
	meshDictionary[part] = {editableMesh, dynamicMesh}

	--when part is destroyed destroy this key as well

	--build the actor
	--[[
	local actor = updateActor:Clone()
	actor.Parent = actorsFolder
	actor.PartValue.Value = part
	actor.UpdateLOSPart.Enabled = true
	actors[part] = actor
	]]--

	return meshDictionary[part]
end

local HiddenLOSTagged = CollectionService:GetTagged("HiddenFromLOS")
CollectionService:GetInstanceAddedSignal("HiddenFromLOS"):Connect(function(part)
	table.insert(HiddenLOSTagged, part)
end)

--get a constantly updating collection of walls:
local allLOSblockers = {}
local allLOSdict = {}

local StrongWallDict = {}
do
for i, part in ipairs(CollectionService:GetTagged("StrongWall")) do
	StrongWallDict[part] = true
	wallPartAdded(part)
end
CollectionService:GetInstanceAddedSignal("StrongWall"):Connect(function(part)
	StrongWallDict[part] = true
	wallPartAdded(part)
end)
CollectionService:GetInstanceRemovedSignal("StrongWall"):Connect(function(part)
	StrongWallDict[part] = false
	wallPartRemoved(part)
end)
end

local WallDict = {}
do
for i,part in ipairs(CollectionService:GetTagged("Wall")) do
	WallDict[part] = true
	wallPartAdded(part)
end
CollectionService:GetInstanceAddedSignal("Wall"):Connect(function(part)
	WallDict[part] = true
	wallPartAdded(part)
end)
CollectionService:GetInstanceRemovedSignal("Wall"):Connect(function(part)
	WallDict[part] = false
	wallPartRemoved(part)
end)
end
	
local LOSBlockerDict = {}
do
for i,part in ipairs(CollectionService:GetTagged("LOSBlocker")) do
	LOSBlockerDict[part] = true	
	wallPartAdded(part)
end
CollectionService:GetInstanceAddedSignal("LOSBlocker"):Connect(function(part)
	LOSBlockerDict[part] = true	
	wallPartAdded(part)
end)
CollectionService:GetInstanceRemovedSignal("LOSBlocker"):Connect(function(part)
	LOSBlockerDict[part] = false
	wallPartRemoved(part)
	end)
end

function wallPartAdded(part)
	if allLOSdict[part] then return end
	table.insert(allLOSblockers, part)
	allLOSdict[part] = true
end

function wallPartRemoved(part)
	if StrongWallDict[part] or WallDict[part] or LOSBlockerDict[part] then return end
	if allLOSdict[part] then 
		table.remove(allLOSblockers, table.find(allLOSblockers, part))
		allLOSdict[part] = false
	end
	
end

--get all possible emitters (cameras and such, however only focus will be used at one time)
local LOSemitters = {}
do
	for i,part in ipairs(CollectionService:GetTagged("LOSEmitter")) do
		table.insert(LOSemitters, part)
	end
	CollectionService:GetInstanceAddedSignal("LOSEmitter"):Connect(function(part)
		table.insert(LOSemitters, part)
	end)
	CollectionService:GetInstanceRemovedSignal("LOSEmitter"):Connect(function(part)
		table.remove(LOSemitters, table.find(LOSemitters, part))
	end)
end

function m.update()
	local focus = m.LOSFocus

	--get all LOS blocking parts (allLOSblockers)

	--if not meshDictionary[focus] then buildActorAndMesh(focus) end
	m.updateLOSPart(focus, focusEditableMesh, focusDynamicMesh, allLOSblockers)
	--actors[focus]:SendMessage("Update", focus, focusEditableMesh, focusDynamicMesh, allLOSblockers)

	--possible emitters are in LOSemitters

	for i, part in ipairs(LOSemitters) do
		if part ~= focus then
			--grab the meshes to use
			local success
			local meshes = meshDictionary[part]

			if not meshes then
				success, meshes = pcall(buildActorAndMesh, part)
				if not success then continue end
			end

			m.updateLOSPart(part, meshes[1], meshes[2], allLOSblockers)
			--actors[focus]:SendMessage("Update", part, meshes[1], meshes[2], allLOSblockers)
		end
	end
	
	debug.profilebegin("LOS Hiding")
	
	HideModels.updateHidden(viewshapeDictionary)
	--[[
	for i, part in ipairs(HiddenLOSTagged) do
		local cachedInfo = hiddenDictionary[part]
		if not cachedInfo then
			cachedInfo = {}
			hiddenDictionary[part] = cachedInfo

			--grab original transparencies if it's a model
			if part:IsA("Model") or part:IsA("Tool") then
				cachedInfo.Parts = {}
				cachedInfo.OriginalTransparencies = {}
				for i, child in ipairs(part:GetDescendants()) do
					if child:IsA("BasePart") then
						table.insert(cachedInfo.Parts, child)
						cachedInfo.OriginalTransparencies[child] = child.Transparency
					end
				end
			else
				cachedInfo.OriginalTransparency = part.Transparency
			end

			local partAdded = part.DescendantAdded:Connect(function(newPart)
				if newPart:IsA("BasePart") then
					table.insert(cachedInfo.Parts, newPart)
					cachedInfo.OriginalTransparencies[newPart] = newPart.Transparency
				end
			end)
		end

		local isInside = false


		if part:IsA("Model") or part:IsA("Tool") then
			local hitbox
			if part:IsA("Model") then hitbox = part:FindFirstChild("Torso") end
			if part:IsA("Tool") then hitbox = part:FindFirstChild("ToolHandle") end
			
			if hitbox then
				isInside = m.isVectorInLOS(viewshapeDictionary, hitbox.Position)
			else
				continue
			end

		else
			isInside = m.isVectorInLOS(viewshapeDictionary, part.Position)
		end

		if isInside == true then
			--it is shown
			if part:IsA("Model") or part:IsA("Tool") then
				for i, part in ipairs(cachedInfo.Parts) do
					part.Transparency = cachedInfo.OriginalTransparencies[part]
				end
			else
				part.Transparency = cachedInfo.OriginalTransparency
			end
		elseif isInside == false then
			--it is not shown
			if part:IsA("Model") or part:IsA("Tool") then
				for i, part in ipairs(cachedInfo.Parts) do
					part.Transparency = 1
				end
			else
				part.Transparency = 1
			end
		end

	end
	]]--
	
	debug.profileend()

end


function m.updateLOSPart(focus, editableMesh, dynamicMesh, LOSblockers)
	debug.profilebegin("LOS System")

	--exceptions for if LOS is disabled/unspecified
	if not enabled then
		--no visible parts
		debug.profileend()
		return
	elseif not focus then
		--block all view
		debug.profileend()
		return
	end

	--main update

	--collect all information
	local Enabled : boolean			  = getValue(focus, "m_Enabled")
	local ViewRange : number		  = getValue(focus, "m_ViewRange")
	local ViewAngle : number		  = getValue(focus, "m_ViewAngle")
	local PeripheralRange : number	  = getValue(focus, "m_PeripheralRange")
	local RotationDependent : boolean = getValue(focus, "m_RotationDependent")
	local FixedAngle : number		  = getValue(focus, "m_FixedAngle") or 0
	local ViewColor : Color3		  = getValue(focus, "m_ViewColor")
	local ViewHeight : number		  = getValue(focus, "m_ViewHeight")
	local PRECISE					  = getValue(focus, "m_PreciseMethod")
	local INSIDEOUT					  = getValue(focus, "m_RenderInsideOut")

	local position = focus.Position --+ Vector3.new(0, ViewHeight-focus.Position.Y, 0)


	--find the angle numbers for this scanPoint
	local facingAngle = nil
	local leftAngle, rightAngle = nil

	--find angle number
	if RotationDependent and focus.Parent == LocalPlayer.Character then
		--local cframe = focus.CFrame
		--local x, y, _ = cframe:ToEulerAnglesXYZ()
		--facingAngle = -y - math.pi/2
		--if math.abs(x)>3 then facingAngle = -facingAngle end
		local facingVector = Crosshair.m_crosshairWorldVector --Crosshair.m_activeCrosshairWorldVector or 
		if not facingVector then return end --wait a bit before running

		local worldVector2 = Vector2.new(facingVector.X, facingVector.Z)
		local centerVector2 = Vector2.new(focus.Position.X, focus.Position.Z)
		facingAngle = Line.vector2Angle(centerVector2, worldVector2)

	elseif RotationDependent then
		local cframe = focus.CFrame
		local x, y, _ = cframe:ToEulerAnglesXYZ()
		facingAngle = -y - math.pi/2
		if math.abs(x)>3 then facingAngle = -facingAngle end
	else
		--for fixedAngle
		--do later lmao
	end

	--use range to spread out and get the 2 nums
	local offset = math.rad(ViewAngle)
	leftAngle  = Viewshape.checkForLoopback(facingAngle-offset)
	rightAngle = Viewshape.checkForLoopback(facingAngle+offset)

	local currentViewshape = Viewshape.new(position, leftAngle, rightAngle, ViewRange, PeripheralRange)
	--currentViewshape:testDisplay()

	--find all applicable parts
	debug.profilebegin("LineGeneration")
	local addedLines = 0

	--generate lines for all wall parts

	local lineTable = {}
	for i, part in ipairs(LOSblockers) do		
		local line1, line2 = Line.new(currentViewshape, part)
		if line1 then
			table.insert(lineTable, line1)
		end
		if line2 then
			table.insert(lineTable, line2)
		end
	end
	debug.profileend()
	--currentViewshape:testDisplayLines(14, lineTable)

	if PRECISE then
		for i, line in ipairs(lineTable) do
			--currentViewshape:insertLineIntoViewshape(line)

			--currentViewshape:insertLineIntoViewshape(line)
			currentViewshape:insertLineIntoViewshape(line)
			--print(response)
			--if not success then return end
		end

		--currentViewshape:preciseGenerateViewshapeVertices()
	else
		--intersect the lines, restricting to only the lines that may be in the viewshape
		--this may destroy or duplicate some lines
		debug.profilebegin("LineIntersection")
		local insideLineTable = currentViewshape.m_lines
		--if currentViewshape.m_viewRange == currentViewshape.m_peripheralRange or currentViewshape.m_leftAngle == currentViewshape.m_rightAngle then
		--insideLineTable = lineTable
		--else
		for i, line in ipairs(lineTable) do
			local line1, line2 = currentViewshape:intersectLineWithViewshape(line)

			if line1 then table.insert(insideLineTable, line1); addedLines += 1 end
			if line2 then table.insert(insideLineTable, line2); addedLines += 1 end
		end

		--currentViewshape:testDisplayLines(18)
		debug.profileend()

		--insert all lines into viewshape
		debug.profilebegin("LineInsertion")

		if addedLines ~= 0 then
			currentViewshape:optimizedGenerateViewshapeVertices()
		end
		debug.profileend()
	end

	--currentViewshape:testDisplayLines(18)

	--render viewshape
	debug.profilebegin("ViewshapeRendering")

	--currentViewshape:testDisplay(20)
	--print(unpack(currentViewshape.m_vertices))

	if focus.Name == "HumanoidRootPart" then
		currentViewshape:display(editableMesh, dynamicMesh, INSIDEOUT)	
	else
		currentViewshape.m_topRenderHeight = currentViewshape.m_topRenderHeight+0.5
		currentViewshape:display(editableMesh, dynamicMesh, INSIDEOUT)	
	end

	debug.profileend()

	viewshapeDictionary[focus] = currentViewshape

	debug.profileend() --LOS system
end


function m.isVectorInLOS(viewshapeDictionary : {BasePart : viewshape}, vector : Vector3, onlyInFocus : boolean) : boolean
	--local LOSTagged = CollectionService:GetTagged("LOSEmitter")

	local isInside = false
	for part, viewshape in pairs(viewshapeDictionary) do
		if onlyInFocus and part ~= m.LOSFocus then continue end

		--local meshExists = meshDictionary[part]
		--if not meshExists then continue end

		local vector2conv = Vector2.new(vector.X, vector.Z)

		local tempPoint = {
			m_pos = vector2conv;
			m_dist = (vector2conv-viewshape.m_center).Magnitude;
			m_angle = Line.vector2Angle(viewshape.m_center, vector2conv);
		}
		
		--maxVector and minVector form a bounding box, which can be used for quicker calculations
		local maxVector = viewshape.m_maxVector
		local minVector = viewshape.m_minVector
		if 	   vector2conv.X > maxVector.X
			or vector2conv.Y > maxVector.Y
			or vector2conv.X < minVector.X
			or vector2conv.Y < minVector.Y
		then
			--there is no way for the line to intersect with the viewshape because it's outside the bounding box
			continue
		end
		
		--if its too close to the center, then it's good
		if (tempPoint.m_pos - viewshape.m_center).Magnitude < 0.5 then return true end
		
		local isInside = viewshape:lineRaycast(nil, nil, tempPoint) == 1--viewshape:isVector2InViewshape(vector2conv)
		if isInside then return true end
	end
	return false

end

function createValue(name, value, parent)

	--check if it exists already
	if parent:FindFirstChild(name) then
		parent[name].Value = value
		return parent[name]
	end

	--turn into object
	local instanceType = nil
	local valueType = typeof(value)

	local castDict = {
		["string"] = "StringValue";
		["number"] = "NumberValue";
		["boolean"] = "BoolValue";
		["Instance"] = "ObjectValue";
		["CFrame"] = "CFrameValue";
		["Vector3"] = "Vector3Value";
		["Color3"] = "Color3Value";
	}

	instanceType = castDict[valueType]
	if instanceType == nil then
		error("Unable to cast "..value.." to value object")
	end

	local instance = Instance.new(instanceType)
	instance.Value = value
	instance.Name = name
	instance.Parent = parent
	return instance
end

function getValue(part, name)
	--just return if you can find it for now
	if part:FindFirstChild(name) then
		return part[name].Value
	else
		return nil
	end

end

return m
