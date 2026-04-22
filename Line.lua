local m = {}

--[[

object file for the line used to represent each blocker for view
all objects are represented by a line segment for their view blockers
these aren't actually real objects, more like containers since so many need to be made per frame

modify this file to add new hitboxes to existing objects

]]--

type Line = {
	LeftPoint  : Vector2;
	RightPoint : Vector2;
	LeftAngle  : number;
	RightAngle : number;
	LeftDistance  : number;
	RightDistance : number;
	
	ClosestPoint : Vector2?;
	ClosestDist : number?;
}

--constructors
m.new = nil --constructor from a part instance
m.newFromVectors = nil --constructor from 2 vector2s

--getPartCorners
--takes a part and returns it's radius and an array of all 4 of it's corners
--indexes past 4 include extra flags for doors, etc
local getPartCorners = nil

--helper functions
--takes radius and angle and returns a point on the unit circle
local pointFromCircle = nil

--returns angle between 2 vectors, using the first as the origin
local vector2Angle = nil

--vector3 -> vector2
local vector3to2 = nil

--rotates a vector around the origin
local rotateVector2 = nil

--first 2 vectors, create a line, test which side of the line the 3rd vector is on
local lineTest = nil


local TEST = require(script.Parent.TEST)


--locally capture all "UseFullCornersLOS" tags
local USE_ALL_CORNERS_TAG = "UseFullCornersLOS"
local CollectionService = game:GetService("CollectionService")

local allCornersObjects : {[BasePart | Model] : true} = {}
for i, part : BasePart | Model in ipairs(CollectionService:GetTagged(USE_ALL_CORNERS_TAG)) do
	allCornersObjects[part] = true
end
CollectionService:GetInstanceAddedSignal(USE_ALL_CORNERS_TAG):Connect(function(part)
	allCornersObjects[part] = true
end)
CollectionService:GetInstanceRemovedSignal(USE_ALL_CORNERS_TAG):Connect(function(part)
	allCornersObjects[part] = nil
end)

--** IMPLEMENTATION **--

function m.new(viewshape : Viewshape, part) : Line?
	
	--first check if this is even needed
	local partRadius, partCorners = getPartCorners(part)

	--maxVector and minVector form a bounding box, which can be used for quicker calculations
	local maxVector = viewshape.m_maxVector
	local minVector = viewshape.m_minVector

	if 	  #partCorners == 4
		and ((partCorners[1].X > maxVector.X and partCorners[2].X > maxVector.X and partCorners[3].X > maxVector.X and partCorners[4].X > maxVector.X) 
		or (partCorners[1].X < minVector.X and partCorners[2].X < minVector.X and partCorners[3].X < minVector.X and partCorners[4].X < minVector.X) 
		or (partCorners[1].Y > maxVector.Y and partCorners[2].Y > maxVector.Y and partCorners[3].Y > maxVector.Y and partCorners[4].Y > maxVector.Y) 
		or (partCorners[1].Y < minVector.Y and partCorners[2].Y < minVector.Y and partCorners[3].Y < minVector.Y and partCorners[4].Y < minVector.Y)) 
	then
		--there is no way for the line to intersect with the viewshape because it's outside the bounding box
		return nil
	end
	
	--identify what kind of part this is
	local identifier : string = nil
	if part:IsA("Part") then
		local shape = part.Shape
		if shape == Enum.PartType.Block then
			identifier = "rectangle"
		elseif shape == Enum.PartType.Wedge then 
			identifier = "wedge"
		elseif shape == Enum.PartType.Ball or shape == Enum.PartType.Cylinder then
			identifier = "circle"
		end
	elseif part:IsA("MeshPart") then
		identifier = "rectangle"
	end

	local center = viewshape.m_center
	local partPosition2d = vector3to2(part.Position)
	local distance = (center-partPosition2d).Magnitude

	--there are only really 2 points on every part that need to be checked on every object for LOS blocking
	--these 2 points form a wall which you wont be able to see through, and is represented as a "Line"

	local scanPoint1, scanPoint2 = nil, nil
	local middlePoint = nil
	
	if partCorners and #partCorners == 2 then
		scanPoint1 = partCorners[1]
		scanPoint2 = partCorners[2]
	elseif identifier == "rectangle" then

		--the 2 important points depend on whether the rectangle faces the point
		local facing = false
		local holder = {}
		for i=1, 4 do
			--do an edge comparison using every line, if all parallel lines have the same sign, then the point is in a corner
			--else, it's facing
			local nextPoint = i+1
			if i==4 then nextPoint = 1 end

			local vertex1 = partCorners[i]
			local vertex2 = partCorners[nextPoint]

			local result = math.sign(lineTest(vertex1, vertex2, center))

			if i>2 then
				--compare to the parallel one
				if result == holder[i-2] then
					facing = true

					--set scan points here, i is needed to determine

					--this is the part face that's looking at the sight point
					--read results from holder in order to determine which

					local testI = 5-i
					local prev = holder[testI]
					local function cycle(i)
						if i>4 then return i-4 else return i end
					end
					if prev > 0 then
						scanPoint1 = partCorners[testI]
						scanPoint2 = partCorners[cycle(testI+1)]
					else
						scanPoint1 = partCorners[cycle(testI+2)]
						scanPoint2 = partCorners[cycle(testI+3)]
					end

					break
				end
			else
				--store in holder for checking
				holder[i] = result
			end
		end

		if not facing then
			--scan points are the 2nd and 3rd closest corners!
			local highestIndex = 1
			local highestDist = (partCorners[1]-center).Magnitude
			local lowestIndex = 1
			local lowestDist = highestDist
			for i=2, 4 do
				local dist = (partCorners[i]-center).Magnitude
				if dist > highestDist then
					highestDist = dist
					highestIndex = i
				end
				if dist < lowestDist then
					lowestDist = dist
					lowestIndex = i
				end
			end

			local firstSet = false
			for i=1, 4 do
				if i ~= highestIndex and i ~= lowestIndex then
					if not firstSet then
						scanPoint1 = partCorners[i]
						firstSet = true
					else
						scanPoint2 = partCorners[i]
						break
					end
				end
			end
			
			if allCornersObjects[part] then
				middlePoint = partCorners[lowestIndex]
			end
		end

	elseif identifier == "wedge" then
		--the hypotenuse forms a diagonal wall, anything infront of the hypotenuse gets the 2 points on the front face of the triangle

		--the corner opposite the hypotenuse also gets those 2 points

		--edge comparison the hypotenuse & the leg point
		--if both have the same sign, then distance sort, else it's the hypotenuse points



		--the rest get the 2 closest points to them
	elseif identifier == "circle" then
		--this is done using calculus, the point is found by the 2 points on the circle who have a tangent that intersects with the current point

		--equation notes:
		--https://www.desmos.com/calculator/uwhsqmy9dq
		
		local angleToPart = vector2Angle(center, partPosition2d)
		--distance already calculated
		
		local diameter = part.Size.Y
		local radius = diameter/2

		local x = radius^2/distance
		local y = math.sqrt(radius^2-x^2)

		local localVector1 = rotateVector2(Vector2.new(x,y) , angleToPart+math.pi)
		local localVector2 = rotateVector2(Vector2.new(x,-y) , angleToPart+math.pi)

		scanPoint1 = partPosition2d + localVector1
		scanPoint2 = partPosition2d + localVector2

	end

	if not scanPoint1 or not scanPoint2 then error("Scan points unable to be found for ", part) end
	
	local scanAngle1 = vector2Angle(center, scanPoint1)
	local scanAngle2 = vector2Angle(center, scanPoint2)
	
	if (math.abs(scanAngle1-scanAngle2)>math.pi) ~= (scanAngle1 > scanAngle2) then
		scanAngle2, scanAngle1 = scanAngle1, scanAngle2
		scanPoint2, scanPoint1 = scanPoint1, scanPoint2
	end
	
	local scanDistance1 = (scanPoint1-center).Magnitude
	local scanDistance2 = (scanPoint2-center).Magnitude
	
	if not middlePoint then
		local newLine : Line = {
			LeftPoint  = scanPoint1;
			RightPoint = scanPoint2;
			LeftAngle  = scanAngle1;
			RightAngle = scanAngle2;
			LeftDistance  = scanDistance1;
			RightDistance = scanDistance2;
		}
	
		return newLine
	else
		local middleAngle = vector2Angle(center, middlePoint)
		local middleDistance = (middlePoint-center).Magnitude
		
		local newLine1 : Line = {
			LeftPoint  = scanPoint1;
			RightPoint = middlePoint;
			LeftAngle  = scanAngle1;
			RightAngle = middleAngle;
			LeftDistance  = scanDistance1;
			RightDistance = middleDistance;
		}
		
		local newLine2 : Line = {
			LeftPoint  = middlePoint;
			RightPoint = scanPoint2;
			LeftAngle  = middleAngle;
			RightAngle = scanAngle2;
			LeftDistance  = middleDistance;
			RightDistance = scanDistance2;
		}

		return newLine1, newLine2
	end
	
end

function m.newFromVectors(viewshape : Viewshape, scanPoint1, scanPoint2, closestVector) : Line
	
	local center = viewshape.m_center
	
	local scanAngle1 = vector2Angle(center, scanPoint1)
	local scanAngle2 = vector2Angle(center, scanPoint2)

	if (math.abs(scanAngle1-scanAngle2)>math.pi) ~= (scanAngle1 > scanAngle2) then
		scanAngle2, scanAngle1 = scanAngle1, scanAngle2
		scanPoint2, scanPoint1 = scanPoint1, scanPoint2
	end

	local scanDistance1 = (scanPoint1-center).Magnitude
	local scanDistance2 = (scanPoint2-center).Magnitude

	local newLine : Line = {
		LeftPoint  = scanPoint1;
		RightPoint = scanPoint2;
		LeftAngle  = scanAngle1;
		RightAngle = scanAngle2;
		LeftDistance  = scanDistance1;
		RightDistance = scanDistance2;
		
		ClosestPoint = closestVector;
	}
	
	return newLine
	
end

function m.newBaseLine(viewshape : Viewshape, 
	leftPoint, rightPoint,
	leftAngle, rightAngle, 
	leftDistance, rightDistance,
	angleRadius
)
	local line : Line = {
		LeftPoint = leftPoint;
		RightPoint = rightPoint;
		LeftAngle = leftAngle;
		RightAngle = rightAngle;
		LeftDistance = leftDistance;
		RightDistance = rightDistance;
	}	
	
	--now determine closest point and closest dist
	
	--hypotenuse = angleRadius, angle = half of spacing dist
	
	return line
	
end

local precalcPartCorners = {}
m.partParameters = {}
function m.getPartCorners(part) : {Vector2}

	if precalcPartCorners[part] then
		return precalcPartCorners[part][1], precalcPartCorners[part][2]
	end
	
	local partParameters = m.partParameters[part]
	if not partParameters then
		partParameters = {
			["PartType"] = part:FindFirstChild("ObjectType");
			["TwoDim"] = part:FindFirstChild("2D");
			["HingePart"] = part:FindFirstChild("HingePart");
			["OppositePart"] = part:FindFirstChild("OppositePart");
		}
		m.partParameters[part] = partParameters
	end

	--will have to be modified for wedges, they have weird orientations
	local sizePoint = Vector3.new(part.Size.X/2, 0, part.Size.Z/2)
	local partRadius = sizePoint.Magnitude
	local centerAngle = math.atan(sizePoint.X/sizePoint.Z)

	--a rectangle shape has it's corners on a circle
	--all corners are equidistant

	--points on a circle are found on the unit circle (x = cos, y = sin)
	local pos = Vector2.new(part.Position.X, part.Position.Z)
	local yOrientation = math.rad(part.Orientation.Y)
	local cornerArray = {
		pos + pointFromCircle( partRadius, yOrientation-centerAngle),
		pos + pointFromCircle( partRadius, yOrientation+centerAngle),
		pos + pointFromCircle( partRadius, yOrientation-centerAngle+math.pi),
		pos + pointFromCircle( partRadius, yOrientation+centerAngle+math.pi)
	}

	local partType = partParameters.PartType and partParameters.PartType.Value
	local dimModifier = partParameters.TwoDim
	local faceArray = {}
	local faceNum = 0
	if dimModifier or partType == "Door" then
		local face
		if dimModifier then
			face = dimModifier.Face
		elseif partType == "Door" then
			face = part.EdgeSide.Face
		end

		if face == Enum.NormalId.Back then
			faceArray = {cornerArray[1], cornerArray[2]}
			faceNum = 1.5

		elseif face == Enum.NormalId.Right then
			faceArray = {cornerArray[2], cornerArray[3]}
			faceNum = 2.5

		elseif face == Enum.NormalId.Front then
			faceArray = {cornerArray[3], cornerArray[4]}
			faceNum = 3.5

		elseif face == Enum.NormalId.Left then
			faceArray = {cornerArray[4], cornerArray[1]}
			faceNum = 4.5

		end
	end

	if partType == "Door" then
		local hingePart = partParameters.HingePart
		local oppositePart = partParameters.OppositePart
		if hingePart then
			table.insert(cornerArray, 5, hingePart.Value)
			table.insert(cornerArray, 6, (faceArray[1]+faceArray[2])/2)
			table.insert(cornerArray, 7, oppositePart and oppositePart.Value or false)
		end
	elseif dimModifier then
		cornerArray = faceArray
	end


	if part.Anchored == true then
		precalcPartCorners[part] = {
			partRadius, cornerArray
		}
	end

	return partRadius, cornerArray

end

--display function
function m.testDisplayLine(viewshape, line)
	local height = viewshape.m_height
	local leftTest = TEST.testPart(Vector3.new(line.LeftPoint.X, height+2, line.LeftPoint.Y))
	local test = TEST.testLine(Vector3.new(line.LeftPoint.X, height, line.LeftPoint.Y), Vector3.new(line.RightPoint.X, height, line.RightPoint.Y))
end

--helper function implementation
function m.pointFromCircle(radius, angle) : Vector2
	return Vector2.new( math.sin(angle)*radius, math.cos(angle)*radius )
end

function m.vector2Angle(baseVector : Vector2, angleVector : Vector2) : number
	return math.atan2(angleVector.Y - baseVector.Y, angleVector.X - baseVector.X)
end

function m.vector3to2(vector : Vector3) : Vector2
	return Vector2.new(vector.X, vector.Z)
end

function m.rotateVector2(vector2, angle)
	return Vector2.new(
		vector2.X*math.cos(angle)-vector2.Y*math.sin(angle),
		vector2.X*math.sin(angle)+vector2.Y*math.cos(angle)
	)
end

function m.lineTest(vertex1, vertex2, sightVector)
	return (vertex2.X - vertex1.X) * (sightVector.Y - vertex1.Y) - (sightVector.X - vertex1.X) * (vertex2.Y - vertex1.Y)
end

--local assignment
getPartCorners = m.getPartCorners
pointFromCircle = m.pointFromCircle
vector2Angle = m.vector2Angle
vector3to2 = m.vector3to2
rotateVector2 = m.rotateVector2
lineTest = m.lineTest

return m
