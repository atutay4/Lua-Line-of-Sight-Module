LuaU Line of Sight Module
==================

This is a visualizer for the line of sight of a top down game.    
It uses the exact positions of corners of walls in order to create "obstruction lines", then intersects them with a basic polygon to create the walls of vision.   

Extensive optimizations were done in order to make sure the module can run smoothly every frame on low end devices. On average, generating the Viewshape takes under 0.5 ms, meaning it has little impact on reducing fps and can run very smoothly for all players.   
As long as walls are medium sized (Nothing smaller than around 1 unit), the LOS system is very stable and creates no visual artefacts.   

This module was created in Roblox Studio. A .rbxm file is provided in releases to run this module for yourself.   
The module was exclusively created by me. The [PolyBool](https://github.com/EgoMoose/PolyBool-Lua) repository was used to create a prototype, but is not present in the final build.

<img width="953" height="531" alt="image" src="https://github.com/user-attachments/assets/4fd1942e-ea28-418e-8d76-d38f72f83548" />

The module itself works in 4 distinct steps:


Viewshape.new()
------------------
This function creates the base viewshape without any obstructions. There are variables given to modify this.   
If you wish to make a custom shape, you can modify this function.   

<img width="796" height="632" alt="image" src="https://github.com/user-attachments/assets/17809171-a456-4633-b25b-8ca879744633" />


Line.new(part : BasePart) : Line   
Line.newFromVectors(vect1 : Vector2, vect2 : Vector2) : Line
------------------
Every possible obstruction needs to be contained in a 2D line.   
The BasePart constructor uses an existing 3D object, but the Vector2 constructor can create one from 2D coordinates.   

<img width="777" height="539" alt="image" src="https://github.com/user-attachments/assets/a73fc116-bcc2-463e-8fe8-c0e69043202f" />


Viewshape:intersectLineWithViewshape(line : Line) : Line?, Line?
-------------------
This function inserts every line into the viewshape object for processing.   
Internally, this intersects every single line with the shape created by the Viewshape.new() constructor, then returns the cut down segments.
Nothing needs to be done with the returned Lines from this function, but they can be useful for telling if an obstruction was seen by the line of sight system.   
Nothing will be returned if the line had no intersections and was discarded.   

<img width="820" height="653" alt="image" src="https://github.com/user-attachments/assets/35d3d104-2c9a-46b4-bd78-f67d499f4594" />


Viewshape:optimizedGenerateViewshapeVertices()
-------------------
This does the main work of the module, after inputting a line from intersectLineWithViewshape(), the polygon inside Viewshape will be modified to be "blocked" by every single inputted line.   
Viewshape.m_vertices becomes a circular array of 2D points that represents the polygon that the viewshape has become after being obstructed.   

<img width="1221" height="628" alt="image" src="https://github.com/user-attachments/assets/e675120d-4491-4da2-9551-d45fbbe7ee31" />


Viewshape.display()
------------------
The current implementation uses [Roblox's editable mesh](https://create.roblox.com/docs/reference/engine/classes/EditableMesh) to display the generated Polygon.   
This creates the visualization that you can see in the first image of the README.   

<img width="953" height="531" alt="image" src="https://github.com/user-attachments/assets/4fd1942e-ea28-418e-8d76-d38f72f83548" />



Sample Run
==================
Here's an example of all the steps in order inside a script:

```lua

function m.updateLOSPart(focus, editableMesh, dynamicMesh, LOSblockers)

	--exceptions for if LOS is disabled/unspecified
	if not enabled then
		--no visible parts
		return
	elseif not focus then
		--block all view
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
	local ViewHeight : number		  = getValue(focus, "m_ViewHeight)
	local INSIDEOUT					  = getValue(focus, "m_RenderInsideOut")

	local position = focus.Position

	--find the angle numbers for this scanPoint
	local facingAngle = nil
	local leftAngle, rightAngle = nil

	--find angle number
	if RotationDependent and focus.Parent == LocalPlayer.Character then
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
	end

	--use range to spread out and get the 2 nums
	local offset = math.rad(ViewAngle)
	leftAngle  = Viewshape.checkForLoopback(facingAngle-offset)
	rightAngle = Viewshape.checkForLoopback(facingAngle+offset)

	local currentViewshape = Viewshape.new(position, leftAngle, rightAngle, ViewRange, PeripheralRange)
	--currentViewshape:testDisplay() Displaying here will display the image from Viewshape.new()!

	--find all applicable parts
	--generate lines for all wall parts
    local addedLines = 0
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
  	--currentViewshape:testDisplayLines(14, lineTable) Displaying here shows the image from the Line constructors!
  
  	
    --intersect the lines, restricting to only the lines that may be in the viewshape
    --this may destroy or duplicate some lines
    local insideLineTable = currentViewshape.m_lines
    for i, line in ipairs(lineTable) do
      local line1, line2 = currentViewshape:intersectLineWithViewshape(line)
  
      if line1 then table.insert(insideLineTable, line1); addedLines += 1 end
      if line2 then table.insert(insideLineTable, line2); addedLines += 1 end
    end
    --currentViewshape:testDisplayLines(14, insideLineTable) This displays the intersect lines step!


    --insert all lines into viewshape
    if addedLines ~= 0 then
      currentViewshape:optimizedGenerateViewshapeVertices()
    end
	--currentViewshape:testDisplayLines(18) This displays the final polygon!

	--render viewshape
	if focus.Name == "HumanoidRootPart" then
		currentViewshape:display(editableMesh, dynamicMesh, INSIDEOUT)	
	else
		currentViewshape:display(editableMesh, dynamicMesh, INSIDEOUT)	
	end

	viewshapeDictionary[focus] = currentViewshape

end

```
