hello


The module works in 4 distinct steps:

Viewshape.new()
==================
This function creates the base viewshape without any obstructions. There are variables given to modify this.   
If you wish to make a custom shape, you can modify this function.   

Line Generation
==================
Obstructions need to be made and collected for use inside the module, this requires multiple steps.
First:

Line.new(part : BasePart) : Line
Line.newFromVectors(vect1 : Vector2, vect2 : Vector2) : Line
------------------
These constructors are used to generate a line object.


m.intersectLineWithViewshape(line : Line) : Line?, Line?
-------------------
This does a preliminary step to separate the parts of the line that are inside the viewshape


m.insertLineIntoViewshape(line : Line)
-------------------
This does the main work of the module, after inputting a line from m.intersectLineWithViewshape(), the polygon inside Viewshape will be modified to be "blocked" by the line.



Viewshape.display()
==================
The current implementation uses [Roblox's editable mesh](https://create.roblox.com/docs/reference/engine/classes/EditableMesh) to display the generated Polygon. You can change that in this function if you wish.
