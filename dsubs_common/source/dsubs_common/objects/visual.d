module dsubs_common.objects.visual;

import dsubs_common.api.utils;


enum NamedColor: ubyte
{
	MainHullColor,
	SecondaryHullColor,
	MainBorder,
	SecondaryBorder,
}

enum ContourType: ubyte
{
	ConvexContour,
	Lines,
}

struct Contour
{
	Vector2!(float)[] vertices;
	float line_width;
	ContourType type;
	NamedColor fill_color;
	NamedColor line_color;
}

struct VisualModel
{
	// z-ordered contours, wich form the model.
	// first one is the deepest one.
	Contour[] contours;
}
