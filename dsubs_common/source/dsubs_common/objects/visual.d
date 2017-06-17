module dsubs_common.objects.visual;

public import gfm.math.vector;


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
	vec2f[] vertices;
	float line_width;
	ContourType type;
	NamedColor fill_color;
	NamedColor line_color;
}

struct VisualModel
{
	Contour[] contours;		// z-ordered contours, wich form the model.
}
