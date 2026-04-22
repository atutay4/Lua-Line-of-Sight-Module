local m = {}

--[[

object file for the viewshape, the polygon which represents the viewable area

]]--

--container
type Point = {
	m_pos   : Vector2;
	m_dist  : number;
	m_angle : number;
	m_left  : boolean;
}

--private variables
type Viewshape = {	
	m_meshPart : MeshPart;
	m_vertices : {Point};
	m_lines : {Line};

	m_center : Vector2;
	m_height : number;
	m_topRenderHeight    : number;
	m_bottomRenderHeight : number;
	m_viewRange: number;
	m_peripheralRange: number;

	m_leftAngle  : number;
	m_rightAngle : number;
	m_leftPeriPoint  : Vector2;
	m_rightPeriPoint : Vector2;
	m_leftViewPoint  : Vector2;
	m_rightViewPoint : Vector2;

	m_maxVector : Vector2;
	m_minVector : Vector2;
	
	m_perfectCircle : bool;
	m_leftPeriLine : Line;
	m_rightPeriLine : Line;
	
	--m_preciseSegments : {};
}

--constructor
--uses the angle, view range, and peripheral view to construct the initial view shape
m.new = nil

--intersectLineWithViewshape
--takes a line object, returns another line object or null containing a line which is only inside viewshape
m.intersectLineWithViewshape = nil

--insertLineIntoViewshape
--takes a line object, modifies viewshape so that all vertices behind the line are removed
--do intersectLine first
m.insertLineIntoViewshape = nil

--pointOnViewshapeFromAngle
--takes in an angle, returns the corresponding point on the viewshape
m.pointOnViewshapeFromAngle = nil

--display
--use polygon triangulation to display the viewshape
--constant determines whether editablemesh or mesh triangles are used
m.display = nil

--imports
local AssetService : AssetService = game:GetService("AssetService")
local Line = require(script.Parent.Line)
local PolygonTriangulation = require(script.PolygonTriangulation)
local PolyBool = require(script.PolyBool)
local TEST = require(script.Parent.TEST)

--constants

local FAR_FILL_RANGE = 300
local FILL_RANGE = 100
local USE_EDITABLE_MESH = true
local USE_OG_MESH_SIZE = true
local MESH_OFFSET = 20
local DEBUG_WARNINGS = false
local DEBUG_SHOW_RAYCASTS = false

--defaults
m.m_topRenderHeight    = 9.5
m.m_bottomRenderHeight = -30

--** IMPLEMENTATION **--

--constructor code
local circleSegments = 12
local unitCircle = {}
local unitAngles = {}

for i=1, circleSegments do
	local angle = i * (math.pi * 2 / circleSegments) - math.pi - (math.pi / circleSegments)
	local x = math.cos(angle)
	local z = math.sin(angle)
	unitCircle[i] = Vector2.new(x, z)
	unitAngles[i] = angle
end
table.freeze(unitCircle)
table.freeze(unitAngles)

function m.new(position: Vector3, leftAngle: number, rightAngle: number, viewRange: number, peripheralRange: number)
	local self : Viewshape = {}
	
	--this function's main purpose is to set up the lines list (self.m_lines)
	--a basic version of self.m_vertices is also set, incase no walls are viewed
	
	--instance variables
	self.m_center = Vector2.new(position.X, position.Z)
	self.m_height = position.Y + 3
	self.m_viewRange = viewRange
	self.m_peripheralRange = peripheralRange
	self.m_leftAngle = leftAngle
	self.m_rightAngle = rightAngle

	--rest of code is dedicated to setting m_vertices
	
	--creating lines
	local lineTable = {}
	self.m_lines = lineTable
	
	--save the peripheral lines connect to the vertical lines
	local rightLineLeftPoint = nil --use to watch to add self.m_rightPeriLine
	
	local function insertLine(leftPoint, rightPoint, periLine)

		local line : Line = {
			LeftPoint = leftPoint.m_pos;
			RightPoint = rightPoint.m_pos;
			LeftAngle = leftPoint.m_angle;
			RightAngle = rightPoint.m_angle;
			LeftDistance = leftPoint.m_dist;
			RightDistance = rightPoint.m_dist;

			BaseLine = true;
		}	

		if not (leftPoint == rightLineLeftPoint or periLine) and line.LeftDistance == viewRange then
			--extend the line
			local offset = (line.LeftPoint-line.RightPoint).Unit*3
			line.LeftPoint = line.LeftPoint + offset
			line.RightPoint = line.RightPoint - offset

		end

		table.insert(lineTable, line)

		--check to add self.m_rightPeriLine
		if leftPoint == rightLineLeftPoint then
			self.m_rightPeriLine = line
		end

		return line
	end
	
	--shortcut if range is just a circle
	--
	if viewRange == peripheralRange or leftAngle == rightAngle then
		local vertexTable = table.create(circleSegments, false)
		self.m_perfectCircle = true
		self.m_vertices = vertexTable
		local maxVector, minVector = Vector2.zero, Vector2.zero
		for i, unitVector in ipairs(unitCircle) do
			local unitVector = unitCircle[i]
			local vector = unitVector*peripheralRange
			local angle = unitAngles[i]
			vertexTable[i] = {
				m_pos   = vector + self.m_center;
				m_dist  = peripheralRange;
				m_angle = angle;
				m_baseIndex = true;
			}
			maxVector = Vector2.new(math.max(vector.X, maxVector.X), math.max(vector.Y, maxVector.Y))
			minVector = Vector2.new(math.min(vector.X, minVector.X), math.min(vector.Y, minVector.Y))
		end
		self.m_maxVector = maxVector + self.m_center
		self.m_minVector = minVector + self.m_center
		
		for i=1, #vertexTable, 1 do
			local point = vertexTable[i]
			local previousPoint = vertexTable[i-1]
			if not previousPoint then previousPoint = vertexTable[#vertexTable] end

			insertLine(previousPoint, point, true)
		end
		
		return setmetatable(self, {__index = m})
	end
	--

	--main code
	local vertexTable = table.create(circleSegments+4, false)
	self.m_vertices = vertexTable
	

	--insert functions for the vertexTable
	local insertIndex = 1
	local previousInside = false

	local maxVector, minVector = Vector2.zero, Vector2.zero
	
	
	local function insert(index, vector, distance, angle, baseIndex:number?, skipLine, importantPeriLine)
		--set max and minVector
		maxVector = Vector2.new(math.max(vector.X, maxVector.X), math.max(vector.Y, maxVector.Y))
		minVector = Vector2.new(math.min(vector.X, minVector.X), math.min(vector.Y, minVector.Y))

		--convert vector to a point to place in vertices
		local point : Point = {
			m_pos   = vector + self.m_center;
			m_dist  = distance;
			m_angle = angle;
			
		}
		if baseIndex then
			point.m_baseIndex = baseIndex;
		else
			point.m_line = true;
		end
		vertexTable[index] = point
		
		--now also add a line using the previous index
		if not skipLine then
			local previousPoint = vertexTable[index-1]
			if not previousPoint then return point end
			
			return point, insertLine(previousPoint, point, importantPeriLine)
		end
		
		return point
	end

	local leftInserted = false
	local rightInserted = false
	local function insertLeft()
		if leftInserted then error("Inserted left twice") return end
		leftInserted = true
		local closePoint = m.pointFromCircle(peripheralRange, -leftAngle + math.pi/2)
		local farPoint = closePoint*(viewRange/peripheralRange)

		local leftPoint, leftLine = insert(insertIndex, closePoint, peripheralRange, leftAngle, nil, false, true)
		leftPoint.m_raycastRight = true
		local rightPoint = insert(insertIndex+1, farPoint, viewRange, leftAngle, nil, true)
		rightPoint.m_skipRaycast = true
		
		self.m_leftPeriLine = leftLine
		
		self.m_leftPeriPoint = closePoint + self.m_center
		self.m_leftViewPoint = farPoint   + self.m_center

		insertIndex+=2
	end
	local function insertRight()
		if rightInserted then error("Inserted right twice") return end
		rightInserted = true
		local closePoint = m.pointFromCircle(peripheralRange, -rightAngle + math.pi/2)
		local farPoint = closePoint*(viewRange/peripheralRange)

		local leftPoint = insert(insertIndex, farPoint, viewRange, rightAngle)
		leftPoint.m_skipRaycast = true
		local rightPoint = insert(insertIndex+1, closePoint, peripheralRange, rightAngle, nil, true)
		rightPoint.m_raycastLeft = true
		
		rightLineLeftPoint = rightPoint

		self.m_rightPeriPoint = closePoint + self.m_center
		self.m_rightViewPoint = farPoint   + self.m_center

		insertIndex+=2
	end

	--loop checks whether to use a certain range and whether to insert the left/right points
	for i, unitVector in ipairs(unitCircle) do
		local unitAngle = unitAngles[i]

		--check that the angle doesn't coincide with the left and right angles
		local leftCoinciding = math.abs(unitAngle-leftAngle) < 0.0002
		local rightCoinciding = math.abs(unitAngle-rightAngle) < 0.0002
		if leftCoinciding then 
			insertLeft() 
			--prevent next vertex from also inserting left
			previousInside = true
		end
		if rightCoinciding then 
			insertRight() 
			previousInside = false
		end

		if leftCoinciding or rightCoinciding then
			--point is skipped, and index is not iterated if there is coinciding
			table.remove(vertexTable) -- remove last reserved space
			continue
		end

		--depending on whether inside has changed, insert
		local inside = m.checkIfInside(leftAngle, rightAngle, unitAngle)
		if i==1 then previousInside = inside end

		if inside and previousInside ~= inside then	insertLeft() end
		if not inside and previousInside ~= inside then insertRight() end

		--choose view or peripheral range
		if inside then
			--viewRange
			insert(insertIndex, unitVector*viewRange, viewRange, unitAngle, insertIndex)

		else
			--closeRange
			insert(insertIndex, unitVector*peripheralRange, peripheralRange, unitAngle, insertIndex)

		end

		previousInside = inside
		insertIndex+=1

	end

	--if an insertion didn't happen, do it now
	if not leftInserted then insertLeft() end
	if not rightInserted then insertRight() end
	
	--insert a line for the first and last points
	insertLine(self.m_vertices[#self.m_vertices], self.m_vertices[1])
	
	if self.m_vertices[#self.m_vertices-1].m_angle < 0 then
		local first  = table.remove(self.m_vertices, #self.m_vertices)
		local second = table.remove(self.m_vertices, #self.m_vertices)
		table.insert(self.m_vertices, 1, first)
		table.insert(self.m_vertices, 1, second)
	end

	--convert to global space
	self.m_maxVector = maxVector + self.m_center
	self.m_minVector = minVector + self.m_center
	
	return setmetatable(self, {__index = m})
end

--this function can return nil, one line, or two lines in a tuple
--this cuts down lines so that their endpoints are contained in the viewshape and can be used as corners
function m.intersectLineWithViewshape(self : Viewshape, line : Line) : (Line?, Line?)

	local viewRange = self.m_viewRange
	local peripheralRange = self.m_peripheralRange
	if self.m_perfectCircle then viewRange = peripheralRange end
	local center = self.m_center

	--shortcuts
	if line.LeftDistance < peripheralRange and line.RightDistance < peripheralRange then return line end

	local leftDirectional  = self:isInDirectionalView(line.LeftAngle, line.LeftDistance)
	local rightDirectional = self:isInDirectionalView(line.RightAngle, line.RightDistance)
	if not self.m_perfectCircle and leftDirectional and rightDirectional then return line end


	--maxVector and minVector form a bounding box, which can be used for quicker calculations
	local maxVector = self.m_maxVector
	local minVector = self.m_minVector
	if 	   (line.LeftPoint.X > maxVector.X and line.RightPoint.X > maxVector.X) 
		or (line.LeftPoint.X < minVector.X and line.RightPoint.X < minVector.X) 
		or (line.LeftPoint.Y > maxVector.Y and line.RightPoint.Y > maxVector.Y) 
		or (line.LeftPoint.Y < minVector.Y and line.RightPoint.Y < minVector.Y) 
	then
		--there is no way for the line to intersect with the viewshape because it's outside the bounding box
		return nil
	end


	--gather information
	local closestVector = m.findClosestPoint(line.LeftPoint, line.RightPoint, center)
	line.ClosestPoint = closestVector
	--inLines is whether the closest vector is actually inside the line segment
	local inLines = m.isBetween(line.LeftPoint, line.RightPoint, closestVector)
	local closestDistance = (closestVector-center).Magnitude

	if closestDistance > viewRange then return nil end
	if not inLines and line.LeftDistance > viewRange and line.RightDistance > viewRange then return nil end

	--peripheral radius points (intersections between the line and the peripheral circle)
	local inPeripheralView = closestDistance < peripheralRange
	local periLeftRPoint, periRightRPoint = nil
	local periLeftRAngle, periRightRAngle = nil
	if inPeripheralView then 
		periLeftRPoint, periRightRPoint = m.getCirclePoints(line.LeftPoint, line.RightPoint, center, peripheralRange, closestVector)
		if not periRightRPoint then
			periLeftRPoint, periRightRPoint = nil
			inPeripheralView = false
		else
			periLeftRAngle, periRightRAngle = Line.vector2Angle(center, periLeftRPoint), Line.vector2Angle(center, periRightRPoint)
		end

	end
	
	--view radius points (intersections between the line and the view circle)
	local viewLeftRPoint, viewRightRPoint = nil
	viewLeftRPoint, viewRightRPoint = m.getCirclePoints(line.LeftPoint, line.RightPoint, center, viewRange, closestVector)
	if not viewLeftRPoint or not viewRightRPoint then
		print("no view points")
		return nil
	end


	--outputs
	local leftPoint, rightPoint = nil
	local extraLine = nil
	
	--flags
	--wall is for when a point lands on the circular wall of the viewshape
	local leftWallFlag = false
	local rightWallFlag = false
	--no cast is for when a point lands on the ray walls of the viewshape
	local leftNoCastFlag = false
	local rightNoCastFlag = false

	if inPeripheralView and (inLines or line.LeftDistance < peripheralRange or line.RightDistance < peripheralRange) then
		--closest distance is within the small circle range
		--Line.testDisplayLine(self, line)
		--TEST.testPart(Vector3.new(closestVector.X, 10, closestVector.Y))

		--set if there is a possibility that the line is split into 2
		local canBeInCone = false
		local extendingLeft, extendingRight = false, false

		--check if the leftPoint is kept or shortened
		if line.LeftDistance < peripheralRange then
			--point remains
			leftPoint = line.LeftPoint
		elseif self:isInDirectionalView(periLeftRAngle) and not self.m_perfectCircle then
			--angle to the left is reaching into the cone
			if leftDirectional then
				--scanPoint1 remains, difference is directional is called
				leftPoint = line.LeftPoint

			else
				--determine whether it ends at the intersection of the cone wall or at the arc
				local intersection = m.findIntersection(self.m_leftPeriPoint, self.m_leftViewPoint, line.LeftPoint, line.RightPoint)
				local intersectionValid = (intersection
					and m.isBetween(line.LeftPoint, line.RightPoint, intersection) 
					and m.isBetween(self.m_leftPeriPoint, self.m_leftViewPoint, intersection)) == true

				--distance is pulled from the opposite side of the line, closer one is used
				local intersectionDist = intersectionValid and m.estimateVectorDistance(line.RightPoint, intersection) or nil
				local radiusPointDist  = m.estimateVectorDistance(line.RightPoint, viewLeftRPoint)

				--use intersection or viewRPoint, depending on which one is closer
				if not intersectionDist or radiusPointDist < intersectionDist then
					leftPoint = viewLeftRPoint
					leftWallFlag = true
				else
					leftPoint = intersection
					leftNoCastFlag = true
				end
			end

		else
			canBeInCone = true
			extendingLeft = true
			leftPoint = periLeftRPoint
			leftWallFlag = true

		end

		--do the same for rightPoint
		if line.RightDistance < peripheralRange then
			--point remains
			rightPoint = line.RightPoint
		elseif self:isInDirectionalView(periRightRAngle) and not self.m_perfectCircle then
			--angle to the right is reaching into the cone
			if rightDirectional then
				--scanPoint1 remains, difference is directional is called
				rightPoint = line.RightPoint

			else
				--determine whether it ends at the intersection of the cone wall or at the arc
				local intersection = m.findIntersection(self.m_rightPeriPoint, self.m_rightViewPoint, line.LeftPoint, line.RightPoint)
				local intersectionValid = (intersection
					and m.isBetween(line.LeftPoint, line.RightPoint, intersection) 
					and m.isBetween(self.m_rightPeriPoint, self.m_rightViewPoint, intersection)) == true

				--distance is pulled from the opposite side of the line, closer one is used
				local intersectionDist = intersectionValid and m.estimateVectorDistance(line.LeftPoint, intersection) or nil
				local radiusPointDist  = m.estimateVectorDistance(line.LeftPoint, viewRightRPoint)

				--use intersection or viewRPoint, depending on which one is closer
				if not intersectionDist or radiusPointDist < intersectionDist then
					rightPoint = viewRightRPoint
					rightWallFlag = true
				else
					rightPoint = intersection
					rightNoCastFlag = true
				end
			end

		else
			canBeInCone = true
			extendingRight = true
			rightPoint = periRightRPoint
			rightWallFlag = true

		end

		--math.sign(Helper.lineTest(scanPoint1, scanPoint2, point1)) == math.sign(Helper.lineTest(scanPoint1, scanPoint2, point2))
		if canBeInCone and not self.m_perfectCircle then
			--check that if the line were extended, that it doesn't intersect with the cone

			--check the intersections with the view radius points, if those dont intersect then the line cant intersect with the cone
			local viewLeftRAngle  = Line.vector2Angle(center, viewLeftRPoint)
			local viewRightRAngle = Line.vector2Angle(center, viewRightRPoint)
			
			--there's some kind of error here? keep an eye on this
			--determines if we're reaching on the left or right side of the cone
			local backsideAngle = 0 --this angle is on the complete opposite side of the midpoint of the line
			local left  = extendingLeft--self:isInDirectionalView(viewLeftRAngle)  or self:isInDirectionalView(line.LeftAngle)
			local right = extendingRight --self:isInDirectionalView(viewRightRAngle) or self:isInDirectionalView(line.RightAngle)

			--collect info
			local leftIntersection  = m.findIntersection(self.m_leftPeriPoint, self.m_leftViewPoint, line.LeftPoint, line.RightPoint)
			local rightIntersection = m.findIntersection(self.m_rightPeriPoint, self.m_rightViewPoint, line.LeftPoint, line.RightPoint)

			local leftValid = (leftIntersection
					and m.isBetween(line.LeftPoint, line.RightPoint, leftIntersection) 
					and m.isBetween(self.m_leftPeriPoint, self.m_leftViewPoint, leftIntersection)) == true
			local rightValid = (rightIntersection
					and m.isBetween(line.LeftPoint, line.RightPoint, rightIntersection)
					and m.isBetween(self.m_rightPeriPoint, self.m_rightViewPoint, rightIntersection)) == true
				--warn(leftValid, rightValid)

			--check if the left point possibly extends
			if left and rightValid then

				--a new line segement needs to be added, the only point that needs to be decided is left
				local leftPoint  = nil
				local rightPoint = rightIntersection

				local leftWall = false
				local leftNoCast = false

				local intersectionDist = leftValid and m.estimateVectorDistance(line.RightPoint, leftIntersection) or nil
				local radiusPointDist  = m.estimateVectorDistance(line.RightPoint, viewLeftRPoint)

				if leftDirectional then
					leftPoint = line.LeftPoint

					--the closer point is used
				elseif not intersectionDist or radiusPointDist < intersectionDist then
					leftPoint = viewLeftRPoint
					leftWall = true

				else
					leftPoint = leftIntersection
					leftNoCast = true

				end

				local isPointValid = (leftPoint == leftIntersection or self:isInDirectionalView(Line.vector2Angle(center, leftPoint)))
					and (leftPoint == viewLeftRPoint or (leftPoint-center).Magnitude < self.m_viewRange)

				if isPointValid then
					extraLine = Line.newFromVectors(self, leftPoint, rightPoint)
					extraLine.LeftWallFlag = leftWall
					extraLine.LeftNoCastFlag = leftNoCast
					extraLine.RightNoCastFlag = true
					
				end

			end

			--do the same for the right point
			--if the intersection exists and is actually on the line, then another line segment can be made
			if right and leftValid then

				--a new line segement needs to be added, the only point that needs to be decided is the opposite, right
				local leftPoint  = leftIntersection
				local rightPoint = nil

				local rightWall = false
				local rightNoCast = false

				local intersectionDist = rightValid and m.estimateVectorDistance(line.LeftPoint, rightIntersection) or nil
				local radiusPointDist  = m.estimateVectorDistance(line.LeftPoint, viewRightRPoint)

				if rightDirectional then
					rightPoint = line.RightPoint

					--the closer point is used
				elseif not intersectionDist or radiusPointDist < intersectionDist then
					rightPoint = viewRightRPoint
					rightWall = true

				else
					rightPoint = rightIntersection
					rightNoCast = true

				end

				local isPointValid = (rightPoint == rightIntersection or self:isInDirectionalView(Line.vector2Angle(center, rightPoint)))
					and (rightPoint == viewRightRPoint or (rightPoint-center).Magnitude < self.m_viewRange)

				if isPointValid then
					extraLine = Line.newFromVectors(self, leftPoint, rightPoint, closestVector)
					extraLine.RightWallFlag = rightWall
					extraLine.RightNoCastFlag = rightNoCast
					extraLine.LeftNoCastFlag = true
					
				end

			end

		end

	elseif not self.m_perfectCircle then
		--the closest difference is outside the small range, but might be within the cone
		--this is comparably simple, as it can only intersect with the arc and the cone borders

		--checking left point, see if it extends or not
		if leftDirectional then
			--left point unchanged
			leftPoint = line.LeftPoint

		else
			--check the arc and cone wall 
			local leftIntersection = m.findIntersection(self.m_leftPeriPoint, self.m_leftViewPoint, line.LeftPoint, line.RightPoint)
			local leftIntersectionValid = 
				m.isBetween(line.LeftPoint, line.RightPoint, leftIntersection) 
				and m.isBetween(self.m_leftPeriPoint, self.m_leftViewPoint, leftIntersection)

			local leftAngleValid  = self:isInDirectionalView( Line.vector2Angle(center, viewLeftRPoint) )

			if leftIntersectionValid and leftAngleValid then
				--if both are available estimate distance to the right point and choose the closer!
				local intersectionDist = m.estimateVectorDistance(line.RightPoint, leftIntersection)
				local radiusPointDist  = m.estimateVectorDistance(line.RightPoint, viewLeftRPoint)

				if radiusPointDist < intersectionDist then
					leftPoint = viewLeftRPoint
					leftWallFlag = true
				else
					leftPoint = leftIntersection
					leftNoCastFlag = true
				end

			elseif leftIntersectionValid then
				leftPoint = leftIntersection
				leftNoCastFlag = true

			elseif leftAngleValid then
				leftPoint = viewLeftRPoint
				leftWallFlag = true

			else
				--it is physically impossible for the line to exist
				--print("R1")
				return nil
			end


		end

		--checking right point
		if rightDirectional then
			--left point unchanged
			rightPoint = line.RightPoint

		else
			--check the arc and cone wall 
			local rightIntersection = m.findIntersection(self.m_rightPeriPoint, self.m_rightViewPoint, line.LeftPoint, line.RightPoint)
			local rightIntersectionValid = 
				m.isBetween(line.LeftPoint, line.RightPoint, rightIntersection) 
				and m.isBetween(self.m_rightPeriPoint, self.m_rightViewPoint, rightIntersection)

			local rightAngleValid = self:isInDirectionalView( Line.vector2Angle(center, viewRightRPoint) )

			if rightIntersectionValid and rightAngleValid then
				--if both are available estimate distance to the right point and choose the closer!
				local intersectionDist = m.estimateVectorDistance(line.LeftPoint, rightIntersection)
				local radiusPointDist  = m.estimateVectorDistance(line.LeftPoint, viewRightRPoint)

				if radiusPointDist < intersectionDist then
					rightPoint = viewRightRPoint
					rightWallFlag = true
				else
					rightPoint = rightIntersection
					rightNoCastFlag = true
				end

			elseif rightIntersectionValid then
				rightPoint = rightIntersection
				rightNoCastFlag = true

			elseif rightAngleValid then
				rightPoint = viewRightRPoint
				rightWallFlag = true

			else
				--it is physically impossible for the line to exist
				--print("R2")
				return nil
			end


		end

	end


	--returns
	local returnLine = nil
	if leftPoint and rightPoint then
		returnLine = Line.newFromVectors(self, leftPoint, rightPoint, closestVector)
	end
	returnLine.LeftWallFlag = leftWallFlag
	returnLine.RightWallFlag = rightWallFlag
	returnLine.LeftNoCastFlag = leftNoCastFlag 
	returnLine.RightNoCastFlag = rightNoCastFlag 
	
	--extend the line
	if leftNoCastFlag or rightNoCastFlag then
		local offset = (returnLine.LeftPoint-returnLine.RightPoint).Unit*3
		if leftNoCastFlag then 
			returnLine.OGLeftPoint = returnLine.LeftPoint
			returnLine.LeftPoint = returnLine.LeftPoint + offset 
		end
		if rightNoCastFlag then 
			returnLine.OGRightPoint = returnLine.RightPoint
			returnLine.RightPoint = returnLine.RightPoint - offset 
			
		end
	end
	
	if extraLine and (extraLine.LeftNoCastFlag or extraLine.RightNoCastFlag) then
		local offset = (extraLine.LeftPoint-extraLine.RightPoint).Unit*3
		if extraLine.LeftNoCastFlag then 
			extraLine.OGLeftPoint = extraLine.LeftPoint
			extraLine.LeftPoint = extraLine.LeftPoint + offset 
		end
		if extraLine.RightNoCastFlag then 
			extraLine.OGRightPoint = extraLine.RightPoint
			extraLine.RightPoint = extraLine.RightPoint - offset 
		end
	end

	return returnLine, extraLine

end



--this is an unoptimized temp version, but this will work for now
function m.insertLineIntoViewshape(self : Viewshape, line : Line)
	
	local normalLeft  = line.LeftPoint  - self.m_center
	local normalRight = line.RightPoint - self.m_center
	
	--convert line into a form for polybool to use
	local backDist = self.m_viewRange + 5
	
	local subtractSegments = {
		line.LeftPoint,
		normalLeft*backDist + self.m_center,
		normalRight*backDist + self.m_center,
		line.RightPoint,
	}
	
	local convSegments = {
		regions = {{
			{subtractSegments[1].X, subtractSegments[1].Y},
			{subtractSegments[2].X, subtractSegments[2].Y},
			{subtractSegments[3].X, subtractSegments[3].Y},
			{subtractSegments[4].X, subtractSegments[4].Y},
		}};
		inverted = false;
	}
	
	--functions to assist in conversion
	local function normToBoolPoly(vertexList)
		local simpleList = table.create(#vertexList)
		for i, vertex in ipairs(vertexList) do
			simpleList[i] = {vertex.m_pos.X, vertex.m_pos.Y}
		end

		return {
			regions = {simpleList};
			inverted = false;
		}
	end

	local function boolToNormPoly(vertexList)
		local simpleList = table.create(#vertexList-1)
		local index = 1
		for i, vertex in ipairs(vertexList) do
			local point = Vector2.new(vertex[1], vertex[2])
			if m.estimateVectorDistance(point, self.m_center) < 0.2 then continue end
			simpleList[index] = {
				m_pos = point;
				m_angle = Line.vector2Angle(self.m_center, point);
			}
			index += 1
		end

		return simpleList
	end
	
	--use an abbreviated version of vertices, using only the vertices in the given angle
	--enclosed with m_center
	
	--[[
	--print(self.m_vertices)
	local biggest = #self.m_vertices
	local biggestAngle = self.m_vertices[biggest].m_angle
	for i, point in ipairs(self.m_vertices) do
		if point.m_angle > biggestAngle then
			biggest = i
			biggestAngle = point.m_angle
		end
	end
	
	local leftBorderI,  leftCoinciding,  leftCoinLine  --= findBorderIndex(line.LeftAngle, line.LeftDistance, true)
	leftBorderI = biggest
	for i=biggest, biggest-#self.m_vertices+1, -1 do
		local i = self:cycleList(i)
		local point = self.m_vertices[i]
		local angle = point.m_angle

		if math.abs(line.LeftAngle-angle) < 0.002 or math.abs(line.LeftAngle+angle) < 0.002 then
			leftCoinciding = true
			leftBorderI = i

			if self:cycleList(i-1) ~= i-1 then break end
			local nextPoint = self.m_vertices[i-1]

			if point.m_left or nextPoint.m_left --and point.m_line and nextPoint.m_line 
			then
				leftCoinLine = true
				leftBorderI = i-1
			end
			break

		elseif angle < line.LeftAngle and not m.checkIfInside(line.LeftAngle, line.RightAngle, angle) then
			leftBorderI = i
			break
		end

	end
	
	
	local smallest = 1
	local smallestAngle = self.m_vertices[smallest].m_angle
	for i, point in ipairs(self.m_vertices) do
		if point.m_angle < smallestAngle then
			smallest = i
			smallestAngle = point.m_angle
		end
	end
	
	local rightBorderI, rightCoinciding, rightCoinLine --= findBorderIndex(line.RightAngle, line.RightDistance, false)
	rightBorderI = smallest
	for i=smallest, smallest+#self.m_vertices-1, 1 do
		local i = self:cycleList(i)
		local point = self.m_vertices[i]
		local angle = point.m_angle

		if math.abs(line.RightAngle-angle) < 0.002 then
			rightCoinciding = true
			rightBorderI = i

			if self:cycleList(i+1) ~= i+1 then break end
			local nextPoint = self.m_vertices[i+1]

			if point.m_left or nextPoint.m_left --and point.m_line and nextPoint.m_line 
			then
				rightCoinLine = true
				rightBorderI = i+1
			end
			break

		elseif angle > line.RightAngle and not m.checkIfInside(line.LeftAngle, line.RightAngle, angle) then
			rightBorderI = i
			break
		end

	end
	
	local leftBound  = leftBorderI
	local rightBound = rightBorderI
	local loopingAcrossBreak = leftBorderI > rightBorderI and leftBound ~= rightBound
	if loopingAcrossBreak then rightBound += #self.m_vertices end

	--the entire section from leftIndex to rightIndex is removed
	--then, a new section is generated using leftBound and leftIndex
	--that section is inserted as a replacement
	
	local cutVertices = {}
	for i=leftBound, rightBound, 1 do
		local first = i==leftBound
		local last  = i==rightBound
		local i		= self:cycleList(i)
		
		table.insert(cutVertices, self.m_vertices[i])
		
	end
	table.insert(cutVertices, {
		m_pos = self.m_center})
	--self:testDisplay(18, cutVertices)
	]]--
	
	--[[
	local convVertices = normToBoolPoly(cutVertices)
	local primaryPoly = PolyBool.difference(convVertices, convSegments)
	]]--
	
	local convVertices = normToBoolPoly(self.m_vertices)
	local primaryPoly = PolyBool.difference(convVertices, convSegments)

	--convert back, set self
	if primaryPoly and #primaryPoly.regions ~= 0 then
		--this will remove the center as well
		local newVertices = boolToNormPoly(primaryPoly.regions[1])
		self.m_vertices = newVertices
		
		--this process can reverse the table sometimes for some reason
		--[[
		local flip = true
		local orderedCount = 0
		for i=1, #newVertices-1, 1 do
			local cur = newVertices[i].m_angle
			local next = newVertices[i+1].m_angle
			
			if not cur or not next then continue end

			if cur < next and math.abs(cur-next) > 0.05 then orderedCount+=1 end
			if orderedCount > 4 or orderedCount == #newVertices-2 then
				flip = false
				break
			end
		end
		if flip then m.ReverseTable(newVertices) end
		]]--
		
		--sort so that the angles are right + eliminate triple coinciding points
		--[[
		local first = newVertices[1].m_angle
		local last  = newVertices[#newVertices].m_angle
		while last < first do
			table.insert(newVertices, 1, table.remove(newVertices))
			last = newVertices[#newVertices].m_angle
		end
		]]--
		
		--[[
		local startIndex = self:cycleList(leftBorderI+1)+1
		m.combineTables(self.m_vertices, newVertices, leftBorderI)
		
		--delete the old section of vertices
		local leftDeleteBound  = self:cycleList(leftBorderI+#newVertices)
		local rightDeleteBound = self:cycleList(rightBorderI+#newVertices)
		local insertPoint = leftBorderI+1

		local iterator  = leftDeleteBound

		while iterator ~= leftBorderI and rightDeleteBound ~= leftBorderI do

			self.m_vertices[iterator] = false
			if iterator == rightDeleteBound then
				break
			end

			iterator = self:cycleList(iterator+1)

		end
		
		for i=#self.m_vertices, 1, -1 do
			if not self.m_vertices[i] then
				table.remove(self.m_vertices, i)
			end
		end
		]]--

		--[[
		local addToStart = {}
		for i = #self.m_vertices, 1, -1 do
			local point = self.m_vertices[i]
			
			if point.m_angle < startPoint.m_angle then
				table.insert(addToStart, 1, table.remove(self.m_vertices, i))
			else break end
		end
		m.combineTables(self.m_vertices, addToStart, 1)
		]]
		--print(self.m_vertices)
		--
		--print(self.m_vertices)
		
		--print(newVertices)
		
		
	end
	
	
end

local DISTANCE_ENUM = {
	POINT_CLOSER = 1;
	COINCIDING = 2;
	POINT_FARTHER = 3;
}

local DISTANCE_ENUM_TEST_COLORS = {
	[1] = Color3.new(0.223529, 1, 0.882353);
	[2] = Color3.new(1, 0.619608, 0.4);
	[3] = Color3.new(0.913725, 0.254902, 1);
}

local SWITCH_ENUM = {
	POINT_WALL = 1;
	POINT_LEFT = 2;
	POINT_RIGHT = 3;
}

--using all lines cached into self.m_lines, this function will then generate all m_points
function m.optimizedGenerateViewshapeVertices(self : Viewshape)
	
	--lines should be fully initialized by now, freeze them to ensure no edits
	table.freeze(self.m_lines)
	--vertices should be initialized to a default shape
	local vertexTable = self.m_vertices
	self.m_vertices = {}
	
	--for all of the base vertices, these can get a raycast just on their own and skip their lines
	for i, point in ipairs(vertexTable) do
		
		--the side raycasts ARE NOT WORKING
		if point.m_skipRaycast then continue end
		
		local switchEnum = SWITCH_ENUM.POINT_WALL
		--left and right refers to which way the cast will go, it's actually on the opposite side
		if point.m_raycastLeft then switchEnum = SWITCH_ENUM.POINT_LEFT end
		if point.m_raycastRight then switchEnum = SWITCH_ENUM.POINT_RIGHT end
		
		--if it's one of the wall arrays, it cant ignore
		local ignoreBase = switchEnum == SWITCH_ENUM.POINT_WALL
		
		--but in that case, it needs to ignore the line it was a part of as well
		local ignoreLine = nil
		if point.m_raycastLeft then ignoreLine = self.m_rightPeriLine end
		if point.m_raycastRight then ignoreLine = self.m_leftPeriLine end
		
		self:pointRaycastSwitch(point, switchEnum, ignoreLine, ignoreBase)
		
	end
	
	--raycast for addedlines
	for i, line in ipairs(self.m_lines) do
		
		if line.BaseLine then continue end
		
		for left=1, 2 do
			local isLeft = left==1
			
			local point : Point = {}
			if isLeft then
				point = {
					m_pos = line.LeftPoint;
					m_angle = line.LeftAngle;
					m_dist = line.LeftDistance;
				}
			else
				point = {
					m_pos = line.RightPoint;
					m_angle = line.RightAngle;
					m_dist = line.RightDistance;
				}
			end

			local switchEnum = nil
			if isLeft then switchEnum = SWITCH_ENUM.POINT_LEFT end
			if not isLeft then switchEnum = SWITCH_ENUM.POINT_RIGHT end
			
			--there are flags to edit switch enum
			
			--wall cast
			local ignoreBase = false
			if isLeft and line.LeftWallFlag then switchEnum = SWITCH_ENUM.POINT_WALL; ignoreBase = true end
			if not isLeft and line.RightWallFlag then switchEnum = SWITCH_ENUM.POINT_WALL; ignoreBase = true end
			
			--no cast
			if isLeft and line.LeftNoCastFlag then continue end
			if not isLeft and line.RightNoCastFlag then continue end
			
			self:pointRaycastSwitch(point, switchEnum, line, ignoreBase)
			
			--local part = TEST.testPart(Vector3.new(point.m_pos.X, 12, point.m_pos.Y))
			--print(distance_enum)
			--part.Color = DISTANCE_ENUM_TEST_COLORS[distance_enum]
			--print(distance_enum)
			
		end
		
		
		
	end
	
	--intersect all added lines, all intersections get a wallRaycast
	for i=1, #self.m_lines, 1 do
		local line = self.m_lines[i]
		if line.BaseLine then continue end
		
		for j=i+1, #self.m_lines, 1 do
			local line2 = self.m_lines[j]
			
			local intersectionPoint : Vector2 = m.findIntersection(line.LeftPoint, line.RightPoint, line2.LeftPoint, line2.RightPoint)
			if not intersectionPoint then continue end
			
			local line1Left = line.OGLeftPoint or line.LeftPoint
			local line1Right = line.OGRightPoint or line.RightPoint
			if not m.isBetween(line1Left, line1Right, intersectionPoint) then
				continue
			end
			local line2Left = line2.OGLeftPoint or line2.LeftPoint
			local line2Right = line2.OGRightPoint or line2.RightPoint
			if not m.isBetween(line2Left, line2Right, intersectionPoint) then
				continue
			end
			
			local newPoint = {
				m_pos = intersectionPoint;
				m_angle = Line.vector2Angle(self.m_center, intersectionPoint);
				m_dist = (self.m_center-intersectionPoint).Magnitude;
			}
			
			self:pointRaycastSwitch(newPoint, SWITCH_ENUM.POINT_WALL, line, true, line2)
			
		end
		
	end
	
	--self.m_vertices = vertexTable
	
end

function m.pointRaycastSwitch(self : Viewshape, point, switchEnum, blacklistLine, ignoreBaseFlag, blacklistLine2)

	local distance_enum, closestPoint, closestDist = self:lineRaycast(blacklistLine, ignoreBaseFlag, point, blacklistLine2)

	local testLine
	if DEBUG_SHOW_RAYCASTS then
		testLine = TEST.testLine(Vector3.new(self.m_center.X,5,self.m_center.Y), Vector3.new(point.m_pos.X,5,point.m_pos.Y))
	end

	if switchEnum == SWITCH_ENUM.POINT_WALL and distance_enum == DISTANCE_ENUM.POINT_CLOSER
		or distance_enum == DISTANCE_ENUM.COINCIDING
	then
		if testLine then testLine.Color = Color3.new(0.164706, 0.219608, 1) end
		--print("ADD")
		self:addPoint(point)

	elseif distance_enum == DISTANCE_ENUM.POINT_CLOSER then
		--add point and it's cast
		--print("CAST")
		if testLine then testLine.Color = Color3.new(0.313725, 1, 0.239216) end
		local castPoint = {
			m_pos = closestPoint;
			m_angle = point.m_angle;
			m_dist = closestDist;
		}

		if switchEnum == SWITCH_ENUM.POINT_LEFT then
			--cast point is left
			castPoint.m_left = true
			point.m_right = true
			self:addPoint(castPoint, point)

			--self:addPoint()
		elseif switchEnum == SWITCH_ENUM.POINT_RIGHT then
			--cast point is right
			point.m_left = true
			castPoint.m_right = true
			self:addPoint(point, castPoint)

			--self:addPoint(castPoint)
		else
			warn("no switch_enum match")
		end

	elseif distance_enum == DISTANCE_ENUM.POINT_FARTHER then
		if testLine then testLine.Color = Color3.new(1, 0.929412, 0.14902) end
		--print("NOTHING")
		--do nothing

	else
		warn("no distance_enum match")
	end

end

--takes a point and "raycasts" it to all lines in m_lines
--returns whether the point is covered by a line, if it's coinciding with one, or is infront of all lines
--if the point is closer than the line, this will return an intersection vector, which is the shadow of the point onto the line
function m.lineRaycast(self : Viewshape, blacklistLine, ignoreDefaultLinesFlag, point : Point, blacklistLine2) : (DISTANCE_ENUM, IntersectionVector?, IntersectionDist?)

	local distance = DISTANCE_ENUM.POINT_CLOSER
	local intersectingLine = nil
	local cachedLineIntersections = {}

	for i, line : Line in ipairs(self.m_lines) do

		--ignore the blacklistLine
		if line == blacklistLine or line == blacklistLine2 then continue end

		--if ignoring default lines, ensure that the checking line wasn't made in the new constructor
		if ignoreDefaultLinesFlag and line.BaseLine == true then continue end

		--first, check if the point is within the line's angles
		--
		if not m.checkIfInside(line.LeftAngle-0.02, line.RightAngle+0.02, point.m_angle) then
			continue
		end
		--

		--abbreviated distance check with closestVector!
		--
		if line.ClosestDist and point.m_dist < line.ClosestDist then
			--distance in this case is CLOSER, but it doesn't really matter, just continue
			continue
		end
		--

		--check if it's coinciding
		local intersectionPoint : Vector2 = m.findIntersection(line.LeftPoint, line.RightPoint, self.m_center, point.m_pos)
		if not intersectionPoint then continue end

		if not m.isBetween(line.LeftPoint, line.RightPoint, intersectionPoint) then
			continue
		end
		if not m.isBetween(self.m_center, (point.m_pos-self.m_center)*100+self.m_center, intersectionPoint) then
			continue
		end

		--TEST.testPart(Vector3.new(intersectionPoint.X,5,intersectionPoint.Y))
		cachedLineIntersections[i] = intersectionPoint



		if m.estimateVectorDistance(intersectionPoint, point.m_pos) < 0.4 then
			distance = DISTANCE_ENUM.COINCIDING
			continue
		end
		
		--now use line test to determine if it's infront of the line or not
		local result = self:lineTest(line, point) --true point and center are on the same side of the line
		if result then 
			
			if line.BaseLine == true then
				distance = DISTANCE_ENUM.COINCIDING
				continue
			end
			
			--line is blocked!!! stop it here
			distance = DISTANCE_ENUM.POINT_FARTHER
			intersectingLine = line
			break
		else
			--distance in this case is CLOSER, but it doesn't really matter, just continue
			continue
		end

	end

	if distance ~= DISTANCE_ENUM.POINT_CLOSER then
		return distance
	else
		if next(cachedLineIntersections, nil) == nil then distance = DISTANCE_ENUM.COINCIDING; return distance end
		--if the point was closer, then we need to raycast onto all the line segments

		--loop through all cached line intersections, pull the first one, and that's the intersection vector
		local closestDistance = math.huge
		local closestPoint = nil
		for i, intersectionPoint in pairs(cachedLineIntersections) do
			local pointDistance = (intersectionPoint-self.m_center).Magnitude

			if pointDistance < closestDistance then
				closestDistance = pointDistance
				closestPoint = intersectionPoint
			end
		end

		if DEBUG_SHOW_RAYCASTS then
			local part = TEST.testPart(Vector3.new(closestPoint.X,7,closestPoint.Y))
			part.Color = Color3.new(0, 0.215686, 1)
		end

		return DISTANCE_ENUM.POINT_CLOSER, closestPoint, closestDistance
	end

end

--after the viewshape is generated, a quicker algorithm can be used to determine if a vector is inside the viewshape
--because m_vertices is a sorted list, just find
function m.isVector2InViewshape(self : Viewshape, vector : Vector2) : boolean
	local vertices = self.m_vertices
	local vectorDistance = (vector-self.m_center).Magnitude
	local vectorAngle = Line.vector2Angle(self.m_center, vector);
	
	local rightIndex = 1
	for i, listVertice in pairs(vertices) do

		if listVertice.m_angle >= vectorAngle then
			rightIndex = i
			break
		end

	end
	
	--special case of the angles are equal
	if vertices[rightIndex].m_angle == vectorAngle then
		return vectorDistance < vertices[rightIndex]
	end
	
	local leftIndex = self:cycleList(rightIndex-1)
	
	--using the point on the left and right, the depth in the viewshape can be determined using a line
	local leftDistance = vertices[leftIndex].m_dist
	local rightDistance = vertices[rightIndex].m_dist
	
	local leftAngle = vertices[leftIndex].m_angle
	local rightAngle = vertices[rightIndex].m_angle
	--force left to be less than right, we'll interpolate using that
	if leftAngle>rightAngle then rightAngle += 2*math.pi end
	if leftAngle>vectorAngle then vectorAngle += 2*math.pi end
	
	--now interpolating (leftAngle -> 0, rightAngle -> 1)
	local predictedDistance = leftDistance + rightDistance*( (vectorAngle-leftAngle)/(rightAngle-leftAngle) )
	print(predictedDistance)
	return vectorDistance < predictedDistance
end

function m.addPoint(self : Viewshape, point : Point, rightPoint)
	
	--check the points for merging
	for i, mergePoint in ipairs(self.m_vertices) do
		if m.estimateVectorDistance(mergePoint.m_pos, point.m_pos) < 0.05
			or (rightPoint and m.estimateVectorDistance(mergePoint.m_pos, rightPoint.m_pos) < 0.05)	
			--math.abs(mergePoint.m_angle - point.m_angle) < 0.005	
		then
			--already a point there! delete that point
			table.remove(self.m_vertices, i)
		end
	end

	local angle = point.m_angle
	local insertPoint = #self.m_vertices+1

	for i, listVertice in ipairs(self.m_vertices) do

		if listVertice.m_angle > angle then
			insertPoint = i
			break
		end

	end

	--if coinciding and not left then insertPoint += 1 end
	
	if rightPoint then
		table.insert(self.m_vertices, insertPoint, rightPoint)
	end
	table.insert(self.m_vertices, insertPoint, point)
	
	return true

end

--base : {1, 2, 3}, addition : {4, 5}, index : 2
--base is changed to {1, 4, 5, 2, 3}
--local base = {1, 2, 3} local addition = {4, 5} m.combineTables(base, addition, 2) print(base)
function m.combineTables(base : {}, addition : {}, index : number)
	if index > #base+1 then index = #base+1 end
	if index < 1 then index = 1 end
	
	for i=#addition, 1, -1 do
		table.insert(base, index, addition[i])
	end
end

--display the final viewshape using PolygonTriangulation
--additional optimizations as well to reduce the amount of polygons changed every frame
local boxPoints = {
	Vector2.new(-FILL_RANGE,  FILL_RANGE);
	Vector2.new(FILL_RANGE,   FILL_RANGE);
	Vector2.new(FILL_RANGE,  -FILL_RANGE);
	Vector2.new(-FILL_RANGE, -FILL_RANGE);
}

local boxAngles = {
	Line.vector2Angle(Vector2.zero, boxPoints[1]);
	Line.vector2Angle(Vector2.zero, boxPoints[2]);
	Line.vector2Angle(Vector2.zero, boxPoints[3]);
	Line.vector2Angle(Vector2.zero, boxPoints[4]);
}

function m.ReverseTable(t)
	local l = #t
	for i = 1, math.floor(l / 2) do
		local b = l - (i - 1) 
		t[i], t[b] = t[b], t[i]
	end
end


function m.display(self : Viewshape, editableMesh, dynamicMesh, turnInsideOut)
	
	local vertices = self.m_vertices
	
	--1. turn the polygon inside out and find the best spot to place a hole section
	--[[
	local orderedCount = 0
	for i=1, #self.m_vertices-1, 1 do
		local cur = vertices[i].m_angle
		local next = vertices[i+1].m_angle
		
		if cur < next and math.abs(cur-next) > 0.05 then orderedCount+=1 end
		if orderedCount > 4 then
			m.ReverseTable(self.m_vertices)
			break
		end
	end]]
	
	if turnInsideOut then
		m.ReverseTable(self.m_vertices)
		--find farthest vertex
		if #self.m_vertices == 0 then return end
		local farthestDistance = 0
		local farthestIndex = 0
		for i, point in self.m_vertices do
			local vertex = point.m_pos
			local distance = m.estimateVectorDistance(vertex, self.m_center)
			if distance > farthestDistance then
				farthestDistance = distance
				farthestIndex = i
			end
		end
		local farthestVertexClone = table.clone(self.m_vertices[farthestIndex])
		farthestVertexClone.m_bridge = true

		--find the closest box point to that vertex
		local closestBoxIndex = 0
		local closestDistance = math.huge
		for i, point in boxPoints do
			local distance = m.estimateVectorDistance(farthestVertexClone.m_pos, point + self.m_center)
			if distance < closestDistance then
				closestDistance = distance
				closestBoxIndex = i
			end
		end


		--2. modify the viewshape, adding a bridge to the box
		--the 'bridge' flag on a point indicates that the line segment starting from this point has no wall in the mesh
		for j=closestBoxIndex, closestBoxIndex+4 do
			local i = j
			if i > 4 then i = i-4 end

			--incomplete point, distance and angle are not needed
			local newVertex : Point = {
				m_pos    = boxPoints[i] + self.m_center;
				m_bridge = true;
			}

			table.insert(self.m_vertices, farthestIndex, newVertex)
		end
		table.insert(self.m_vertices, farthestIndex, farthestVertexClone)
	end

	--3. from the modified viewshape, display using an editable mesh or instance triangles

	if USE_EDITABLE_MESH then
		--clear editable mesh and move base mesh
		PolygonTriangulation.primeMesh(editableMesh)
		
		--FOR SOME REASON THE SIZE CHANGES RANDOMLY
		if USE_OG_MESH_SIZE then
			dynamicMesh.Size = Vector3.new(2.02*FILL_RANGE, math.abs(self.m_topRenderHeight-self.m_bottomRenderHeight), 2.02*FILL_RANGE)
		else
			dynamicMesh.Size = Vector3.new(1.04, math.abs(self.m_topRenderHeight-self.m_bottomRenderHeight), 1.04)
		end
		
		dynamicMesh.Position = Vector3.new(self.m_center.X, self.m_topRenderHeight, self.m_center.Y)
		--(self.m_topRenderHeight + self.m_bottomRenderHeight)/2

		--build walls, while skipping bridge points
		for i, point in self.m_vertices do
			
			if point.m_bridge then continue end
			local nextPoint = self.m_vertices[self:cycleList(i+1)]
			
			local lowerOffset = self.m_bottomRenderHeight-self.m_topRenderHeight
			
			local p1 = Vector3.new(point.m_pos.X, 0, point.m_pos.Y)
			local p2 = Vector3.new(point.m_pos.X, lowerOffset, point.m_pos.Y)
			local p3 = Vector3.new(nextPoint.m_pos.X, 0, nextPoint.m_pos.Y)
			local p4 = Vector3.new(nextPoint.m_pos.X, lowerOffset, nextPoint.m_pos.Y)
			
			local wall = PolygonTriangulation.getWall(editableMesh)
			PolygonTriangulation.setWallPosition(wall, self, editableMesh, p1, p2, p3, p4)
			
		end
		
		if not turnInsideOut then
			--build walls at boxPoints to fill out the size!
			local drop = Vector3.new(0, -300, 0)
			local lowerOffset = self.m_bottomRenderHeight-self.m_topRenderHeight
			
			local p1 = drop + m.vector2To3(boxPoints[1] + self.m_center) + Vector3.new(0,lowerOffset,0)
			local p2 = p1 + Vector3.new(0, 1, 0)
			local p3 = drop + m.vector2To3(boxPoints[2] + self.m_center) + Vector3.new(0,lowerOffset,0)
			local p4 = p3 + Vector3.new(0, 1, 0)
			
			local wall1 = PolygonTriangulation.getWall(editableMesh)
			PolygonTriangulation.setWallPosition(wall1, self, editableMesh, p1, p2, p3, p4)
			
			local p1 = drop + m.vector2To3(boxPoints[3] + self.m_center) + Vector3.new(0,lowerOffset,0)
			local p2 = p1 + Vector3.new(0, 1, 0)
			local p3 = drop + m.vector2To3(boxPoints[4] + self.m_center) + Vector3.new(0,lowerOffset,0)
			local p4 = p3 + Vector3.new(0, 1, 0)
			
			local wall2 = PolygonTriangulation.getWall(editableMesh)
			PolygonTriangulation.setWallPosition(wall2, self, editableMesh, p1, p2, p3, p4)
		end

		--toss the polygon in polytriangulation to fill the top part
		--PolygonTriangulation.fillShape(self, editableMesh) --using this method causes some gaps
		
		--fill the top
		--
		for i, point in self.m_vertices do
			
			if point.m_bridge then continue end
			local nextPoint = self.m_vertices[self:cycleList(i+1)]
			
			--if (point.m_pos-nextPoint.m_pos).Magnitude < 0.05 then continue end
			local function isLine(point1, point2)
				return ( not turnInsideOut and point1.m_left and point2.m_right ) or ( turnInsideOut and point1.m_right and point2.m_left )
			end
			
			if isLine(point, nextPoint) then continue end
			
			
			--if the point after nextPoint is too close to nextPoint, combine them
			
			local height = self.m_topRenderHeight
			if turnInsideOut then
				--PolygonTriangulation.fillShape(self, editableMesh) 
				--if true then break end
				
				--a rectangle is made, facing outwards with the length of FILL RANGE
				local leftDir = (point.m_pos-self.m_center).Unit
				
				local Xmaximized = leftDir*FILL_RANGE/ math.abs(leftDir.X)
				local Ymaximized = leftDir*FILL_RANGE/ math.abs(leftDir.Y)
				
				local leftFar
				local leftMaxY
				if math.abs( Xmaximized.Y ) > FILL_RANGE then 
					leftFar = Ymaximized
					leftMaxY = true
				else 
					leftFar = Xmaximized
					leftMaxY = false
				end
				leftFar += self.m_center
				
				local rightDir = (nextPoint.m_pos-self.m_center).Unit
				
				local Xmaximized = rightDir*FILL_RANGE/ math.abs(rightDir.X)
				local Ymaximized = rightDir*FILL_RANGE/ math.abs(rightDir.Y)

				local rightFar
				local rightMaxY
				if math.abs( Xmaximized.Y ) > FILL_RANGE then 
					rightFar = Ymaximized
					rightMaxY = true
				else 
					rightFar = Xmaximized
					rightMaxY = false
				end
				rightFar += self.m_center
				
				PolygonTriangulation.editableMeshTriangle(self, editableMesh, point.m_pos, rightFar, leftFar, height)
				PolygonTriangulation.editableMeshTriangle(self, editableMesh, rightFar, point.m_pos, nextPoint.m_pos, height)
				
				--might need a triangle in the corner
				if leftMaxY ~= rightMaxY then
					local corner = Vector2.zero
					if not leftMaxY then
						corner = Vector2.new(leftFar.X, rightFar.Y)
					elseif leftMaxY then
						corner = Vector2.new(rightFar.X, leftFar.Y)
					end
					
					PolygonTriangulation.editableMeshTriangle(self, editableMesh, corner, leftFar, rightFar, height)
					
				--if they're opposite sides of each other, then we need to fill 2 corners
				elseif leftMaxY == rightMaxY 
					and ( (rightMaxY and math.sign(leftFar.Y-self.m_center.Y) ~= math.sign(rightFar.Y-self.m_center.Y)) 
						or (not rightMaxY and math.sign(leftFar.X-self.m_center.X) ~= math.sign(rightFar.X-self.m_center.X)) ) then
					
					--which 2 corners?
					local firstCorner, secondCorner = nil, nil
					local errorState = false
					for i, cornerAngle in ipairs(boxAngles) do
						local isInside = m.checkIfInside(point.m_angle, nextPoint.m_angle, cornerAngle)
						if isInside then
							if not firstCorner  then firstCorner = -boxPoints[i]+self.m_center continue end
							if not secondCorner then secondCorner = -boxPoints[i]+self.m_center continue end
							--shouldn't reach this point
							errorState = true
							break
							
						end
					end
					if errorState then continue end
					
					--we have 4 vertices, leftFar, rightFar, and both corners
					--the method to build a polygon out of these vertices is as follows:
					--1. find the centroid (average X, average Y)
					--2. determine angles in relation to centroid
					--3. sort based on angles to get an ordered polygon
					
					local centroid = ( leftFar+rightFar+firstCorner+secondCorner )/4
					
					local angles = {
						{Line.vector2Angle(centroid, leftFar), leftFar};
						{Line.vector2Angle(centroid, rightFar), rightFar};
						{Line.vector2Angle(centroid, firstCorner), firstCorner};
						{Line.vector2Angle(centroid, secondCorner), secondCorner};
					}					
					table.sort(angles, function(first, second)
						return first[1] < second[1];
					end)
					
					PolygonTriangulation.editableMeshTriangle(self, editableMesh, angles[1][2], angles[2][2], angles[3][2], height)
					PolygonTriangulation.editableMeshTriangle(self, editableMesh, angles[1][2], angles[3][2], angles[4][2], height)
					
					
				end
				
			else
				
				--a triangle is made, connecting center and the 2 vertices
				PolygonTriangulation.editableMeshTriangle(self, editableMesh, point.m_pos, nextPoint.m_pos, self.m_center, height)
				
			end
			
		end
		
		--now apply the mesh
		local newMeshPart = AssetService:CreateMeshPartAsync(Content.fromObject(editableMesh), 
			{CollisionFidelity=Enum.CollisionFidelity.Box, RenderFidelity=Enum.RenderFidelity.Precise}
		)
		--newMeshPart.Parent = dynamicMesh
		--print(newMeshPart)
		dynamicMesh:ApplyMesh(newMeshPart)
		
		PolygonTriangulation.disposeMesh(editableMesh)
	else
		--use instance triangles
		
		
	end
	
	--if it was inside out, expand the block to FAR_FILL_RANGE
	if turnInsideOut then
		
	end
	
end

--the rest of the functions are utility functions
function m.testDisplay(self : Viewshape, height : number?, vertList)
	
	if not self.m_vertices[2] or not self.m_vertices[1] then return end
	local startingLine = TEST.testLine(
		Vector3.new(self.m_vertices[1].m_pos.X, 22, self.m_vertices[1].m_pos.Y),
		Vector3.new(self.m_vertices[2].m_pos.X, 19, self.m_vertices[2].m_pos.Y)
	)
	startingLine.BrickColor = BrickColor.White()

	if not height then height = self.m_height end

	local alternate = true
	local vertices = vertList
	if not vertList then vertices = self.m_vertices end
	--print(vertList)
	for i, vertex in vertices do

		local vertex = vertex.m_pos
		local nextVertex = nil
		if i == #vertices then
			nextVertex = vertices[1].m_pos
		else
			nextVertex = vertices[i+1].m_pos
		end

		local lift = Vector3.new(0,0,0)
		
		local offset
		if alternate then
			offset = Vector3.new(0, 0, 0)
		else
			offset = Vector3.new(0, 1, 0)
		end
		local test = TEST.testLine(Vector3.new(vertex.X, height, vertex.Y) + offset, Vector3.new(nextVertex.X, height, nextVertex.Y) + offset)
		alternate = not alternate
		
	end
end

function m.testDisplayLines(self : Viewshape, height : number?, lineList)
	for i, line in lineList or self.m_lines do

		local vertex = line.LeftPoint
		local nextVertex = line.RightPoint
		
		local lift = Vector3.new(0,0,0)
		local offset = Vector3.zero

		local test = TEST.testLine(Vector3.new(vertex.X, height, vertex.Y) + offset, Vector3.new(nextVertex.X, height, nextVertex.Y) + offset)

	end
end

function m.isInDirectionalView(self : Viewshape, scanAngle, scanDistance) : (boolean)
	local viewRange = self.m_viewRange
	local leftAngle = self.m_leftAngle
	local rightAngle = self.m_rightAngle

	--print(angle1, angle2, scanAngle, checkIfInside(angle1, angle2, scanAngle))
	local inDistance = true
	if scanDistance then inDistance = scanDistance < viewRange end
	return m.checkIfInside(leftAngle, rightAngle, scanAngle) and inDistance
end

function m.findIntersection(startPoint1, endPoint1, startPoint2, endPoint2) : (Vector2?)
	local point_1_x1 = startPoint1.X
	local point_1_y1 = startPoint1.Y
	local point_1_x2 = endPoint1.X
	local point_1_y2 = endPoint1.Y
	local point_2_x1 = startPoint2.X
	local point_2_y1 = startPoint2.Y
	local point_2_x2 = endPoint2.X
	local point_2_y2 = endPoint2.Y
	-- m = (y1 - y2) / (x1 - x2)
	local line_1_m = 0
	local line_2_m = 0
	-- b = -(mx1) + y1
	local line_1_b = 0
	local line_2_b = 0
	local intersect_x = 0
	local intersect_z = 0
	local isLineOneVertical = ((point_1_x1 / point_1_x2) % 2) == 1
	local isLineTwoVertical = ((point_2_x1 / point_2_x2) % 2) == 1
	if isLineOneVertical and isLineTwoVertical then
		return
	end
	-- Line 1
	if isLineOneVertical then
		line_2_m = (point_2_y1 - point_2_y2) / (point_2_x1 - point_2_x2)
		line_2_b = -(line_2_m * point_2_x1) + point_2_y1
		intersect_x = point_1_x1
		intersect_z = (line_2_m * intersect_x) + line_2_b
		-- Line 2
	elseif isLineTwoVertical then
		line_1_m = (point_1_y1 - point_1_y2) / (point_1_x1 - point_1_x2)
		line_1_b = -(line_1_m * point_1_x1) + point_1_y1
		intersect_x = point_2_x1
		intersect_z = (line_1_m * intersect_x) + line_1_b
	else
		line_1_m = (point_1_y1 - point_1_y2) / (point_1_x1 - point_1_x2)
		line_2_m = (point_2_y1 - point_2_y2) / (point_2_x1 - point_2_x2)

		if line_1_m == line_2_m then
			return
		end
		line_1_b = -(line_1_m * point_1_x1) + point_1_y1
		line_2_b = -(line_2_m * point_2_x1) + point_2_y1
		intersect_x = (line_2_b - line_1_b) / (line_1_m - line_2_m)
		intersect_z = (line_1_m * intersect_x) + line_1_b

	end

	return Vector2.new(intersect_x, intersect_z)
end

function m._findIntersection(pointS1, pointE1, pointS2, pointE2) : (Vector2?)

	local slope1 = (pointS1.Y - pointE1.Y)/(pointS1.X - pointE1.X)
	local slope2 = (pointS2.Y - pointE2.Y)/(pointS2.X - pointE2.X)

	local x
	local y

	--if the lines are perfectly on the grid, then make an exception
	if pointS1.X - pointE1.X == 0 then
		x = pointS1.X
	elseif pointS2.X - pointE2.X == 0 then
		x = pointS2.X
	else

		--formula to find x
		x = (slope1*pointS1.X - slope2*pointS2.X - pointS1.Y + pointS2.Y) / (slope1 - slope2)
	end
	if not x then return end

	--check for exceptions for z incase both are zero
	if pointS1.Y - pointE1.Y == 0 then
		y = pointS1.Y
	elseif pointS2.Y - pointE2.Y == 0 then
		y = pointS2.Y

	else

		--use the normal line formula
		y = slope1*(x - pointS1.X) + pointS1.Y
	end
	if y ~= y then return end

	return Vector2.new(x, y)
end

function m.findClosestPoint(linePos1, linePos2, checkPos) : (Vector2)
	--check if lines are perfectly horizontal
	if linePos1.X == linePos2.X then
		return Vector2.new(linePos1.X, checkPos.Y)
	elseif linePos1.Y == linePos2.Y then
		return Vector2.new(checkPos.X, linePos1.Y)
	end

	--the closest point is found with a perpendicular line
	local slope = (linePos1.Y - linePos2.Y)/(linePos1.X - linePos2.X)
	local invSlope = (1/slope)
	--a system of equations is made with 2 perpendicular linear equations
	local intersectX = (checkPos.Y - linePos1.Y + slope*linePos1.X + invSlope*checkPos.X)/(slope + invSlope)
	local intersectZ = slope*(intersectX - linePos1.X) + linePos1.Y

	return Vector2.new(intersectX, intersectZ)
end

function m.getCirclePoints(line1, line2, circlePos, circleRad, closestPointV) : (Vector2?, Vector2?)
	if not closestPointV then
		closestPointV = _G.Utils.Helper.findClosestPoint(line1, line2, circlePos)
	end
	local difference = (closestPointV-circlePos)
	local distance = difference.Magnitude
	local direction = difference.Unit
	local horizontalV = Vector2.new(direction.Y, -direction.X)

	if math.abs(distance - circleRad) < 0.02 then
		return closestPointV
	elseif distance < circleRad then
		local horizontalDistance = math.sqrt(circleRad^2-distance^2)
		return closestPointV + horizontalV*horizontalDistance, closestPointV + horizontalV*-horizontalDistance
	elseif distance > circleRad then
		return nil
	end
end

function m.estimateVectorDistance(vector1, vector2) : (number)
	return math.abs(vector1.X-vector2.X) + math.abs(vector1.Y-vector2.Y)
end

function m.isBetween(closingVector1, closingVector2, checkingVector, flex) : (boolean)
	if flex then flex = 0.02 else flex = 0 end
	return ((checkingVector.X >= closingVector1.X-flex and checkingVector.X <= closingVector2.X+flex) 
		or (checkingVector.X <= closingVector1.X+flex and checkingVector.X >= closingVector2.X-flex)) 
		and	((checkingVector.Y >= closingVector1.Y-flex and checkingVector.Y <= closingVector2.Y+flex) 
			or  (checkingVector.Y <= closingVector1.Y+flex and checkingVector.Y >= closingVector2.Y-flex))
end

--checks if the given point and self.m_center are on the same side, if NOT then true!
--if the distance is the same then it's false
function m.lineTest(self: Viewshape, line : Line, point : Point) : (boolean)
	--visualization here: (nvm this didn't work)
	--https://www.desmos.com/calculator/okr6igcuwu

	local nVertexL = line.LeftPoint  - self.m_center
	local nVertexR = line.RightPoint - self.m_center
	local nPoint = point.m_pos - self.m_center

	--exception for vertical lines
	if nVertexL.X == nVertexR.X then
		
		return (nPoint.X < nVertexL.X) ~= (0 < nVertexL.X)
		--[[if nVertexL.X > 0 then
			return nPoint.X > nVertexL.X
		else
			return nPoint.X < nVertexL.X
		end]]--

	end
	
	local slope = (nVertexL.Y - nVertexR.Y)/(nVertexL.X - nVertexR.X)

	local function getValueAtX(x : number)
		return slope*(x - nVertexL.X) + nVertexL.Y
	end

	local zeroVal  = getValueAtX(0)
	local pointVal = getValueAtX(nPoint.X)
	
	return (nPoint.Y < pointVal) ~= (0 < zeroVal)
	--[[ zeroVal > 0 then
		return nPoint.Y > pointVal
	else
		return nPoint.Y < pointVal
	end]]--

end

function m.checkForLoopback(angle) : (number)
	if angle<-math.pi then
		return angle + 2*math.pi
	elseif angle>math.pi then
		return angle - 2*math.pi
	else
		return angle
	end
end

--safely increment/decrement without going over the end/beginning of the list
function m.cycleList(self : Viewshape, index)
	local list = self.m_vertices
	if index < 1 then
		index += #list
	end
	if index > #list then
		index -= #list
	end
	return index
end

function m.checkIfInside(angle1, angle2, checkingAngle)
	if angle1<angle2 then
		return checkingAngle>angle1 and checkingAngle<angle2
	elseif angle1>angle2 then
		return checkingAngle>angle1 or checkingAngle<angle2
	end
end

function m.pointFromCircle(radius, angle)
	return Vector2.new( math.sin(angle)*radius, math.cos(angle)*radius )
end

function m.vector2To3(vector2)
	return Vector3.new(vector2.X, 0, vector2.Y)
end

return m


--extra code segments

--[[

--while 
	
	--[[
	for _, insertion in ipairs(queuedInsertions) do
		local point  = insertion[1]
		
		for i, mergePoint in ipairs(self.m_vertices) do
			if math.abs(mergePoint.m_angle-point.m_angle) < 0.05 then
				table.remove(self.m_vertices, i)
			end
		end
	end
	
	for i, insertion in ipairs(queuedInsertions) do
		local point  = insertion[1]
		local isLeft = insertion[2]
		
		self:addPoint(point, isLeft)
	end]]

	--[[
	table.sort(self.m_vertices, function(point1, point2)
		
		--true if 1 goes before 2
		if math.abs(point1.m_angle-point2.m_angle) < 0.05 then
			if point1.m_left then
				return true
			else
				return false				
			end
		elseif point1.m_angle < point2.m_angle then
			return true
		end
	end)
	
	--self:testDisplay(30)
	
	--now add the new points
	--check if to break the array
	--[[
	split = #queuedInsertions > 1 and queuedInsertions[#queuedInsertions].m_angle < queuedInsertions[1].m_angle or false
	if split then
		
		--find split point
		local splitPoint = 1
		for i=#queuedInsertions, 2, -1 do
			
			local cur  = table.remove(queuedInsertions, i)
			local next = queuedInsertions[i-1]
			table.insert(secondHalf, 1, cur)
			
			if cur.m_angle < next.m_angle and not (cur.m_line and next.m_line) then
				splitPoint = i
				break
			end
		end
		
		--print( unpack(queuedInsertions), unpack(secondHalf) ) 
	end

	--generate the walls for each line, skip bridge points
		--in addition, normalize the points back to mesh space (center)
		--print(self.m_vertices)
		for i, point in self.m_vertices do
			point.m_pos = point.m_pos-self.m_center
			--local cframe = mesh.CFrame:VectorToObjectSpace(vector2To3(vector, 0))
			--vertex.CFrame = cframe
			--vertex.TopV = editableMesh:AddVertex()
			local posVector = Vector3.new(point.m_pos.X, 0, point.m_pos.Y)
			point.m_WallTopV    = editableMesh:AddVertex(posVector + Vector3.new(0,self.m_topRenderHeight,0))
			point.m_WallBottomV = editableMesh:AddVertex(posVector + Vector3.new(0,self.m_bottomRenderHeight,0))
		end


]]--
