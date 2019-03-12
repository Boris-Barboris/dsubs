module dsubs_client.game.entities;

import std.algorithm;
import std.array;
import std.conv: to;
import std.math;
import std.utf;
import std.experimental.logger;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_common.api.entities;
import dsubs_common.api.protocols.backend;

import dsubs_client.core.utils;
import dsubs_client.core.window;
import dsubs_client.render.shapes;
import dsubs_client.render.worldmanager;
import dsubs_client.math.transform;

import dsubs_client.game.kinetic;


class Propulsor
{
	mixin Readonly!(Transform, "transform");
	mixin Readonly!(const(PropulsorTemplate*), "tmpl");

	protected ConvexShape m_shape;

	float targetThrottle = 0.0f;

	this(EntityManager man, string propName)
	{
		m_transform = new Transform();
		m_tmpl = man.m_propTemplates[propName];
		m_shape = man.m_propulsorShapes[propName];
	}

	void update(CameraContext camCtx, long usecsDelta) {}
	abstract void renderBack(Window wnd);
	abstract void renderFront(Window wnd);
}


final class ScrewPropulsor: Propulsor
{
	private
	{
		ubyte m_bladeCount;
		float m_rotorAngle = 0.0;
		float m_angVel = 0.0;
		Transform m_rotTransform;
	}

	this(EntityManager man, string propName, ubyte bladeCount)
	{
		super(man, propName);
		m_bladeCount = bladeCount;
		m_rotTransform = new Transform();
		transform.addChild(m_rotTransform);

		m_blades.length = m_bladeCount;
		float step = 2.0 * PI / m_bladeCount;
		float angle = m_rotorAngle;
		for (int i = 0; i < m_bladeCount; i++)
		{
			m_blades[i] = Blade(angle, cos(angle), sin(angle));
			angle += step;
		}
	}

	private struct Blade
	{
		float angle;
		float bladeCos;
		float bladeSin;
	}

	private Blade[] m_blades;

	override void update(CameraContext camCtx, long usecsDelta)
	{
		m_angVel = cmove(m_angVel, 7.5 * targetThrottle, 2.0, usecsDelta / 1e6);
		double delta = m_angVel * 1e-6 * usecsDelta;
		m_rotorAngle += delta;
		m_rotorAngle = clampAngle(m_rotorAngle);
		foreach (ref blade; m_blades)
		{
			double newAngle = clampAngle(blade.angle + delta);
			blade = Blade(newAngle, cos(newAngle), sin(newAngle));
		}
		// we need to start from the blade wich is the deepest one
		sort!((a, b) => a.bladeSin < b.bladeSin)(m_blades);
	}

	override void renderBack(Window wnd)
	{
		foreach (ref blade; m_blades)
		{
			if (blade.bladeSin >= 0.0)
				break;
			m_rotTransform.scale = vec2d(blade.bladeCos, 1.0);
			m_shape.render(wnd, m_rotTransform.world);
		}
	}

	override void renderFront(Window wnd)
	{
		foreach (ref blade; m_blades)
		{
			if (blade.bladeSin < 0.0)
				continue;
			m_rotTransform.scale = vec2d(blade.bladeCos, 1.0);
			m_shape.render(wnd, m_rotTransform.world);
		}
	}
}


final class PumpPropulsor: Propulsor
{
	private double m_angVel = 0.0;

	this(EntityManager man, string propName)
	{
		super(man, propName);
	}

	override void renderBack(Window wnd) {}

	override void renderFront(Window wnd)
	{
		m_shape.render(wnd, transform.world);
	}
}


private Propulsor createPropulsor(EntityManager man, string propName)
{
	auto tmpl = man.m_propTemplates[propName];
	if (tmpl.type == PropulsorType.SCREW)
		return new ScrewPropulsor(man, propName, tmpl.bladeCount);
	else
		return new PumpPropulsor(man, propName);
}


final class Submarine: WorldRenderable
{
	mixin Readonly!(const(SubmarineTemplate*), "tmpl");

	private Propulsor[] m_propulsors;
	private ConvexShape[] m_shapes;
	private KinematicTrace trace;

	float targetCourse = 0.0f;
	private float m_targetThrottle = 0.0f;

	@property float targetThrottle() const { return m_targetThrottle; }
	@property float targetThrottle(float tgt)
	{
		m_targetThrottle = tgt;
		foreach (p; m_propulsors)
			p.targetThrottle = tgt;
		return tgt;
	}

	this(EntityManager man, string hullName, string propName)
	{
		m_tmpl = man.m_submarineTemplates[hullName];
		m_shapes = man.m_submarineShapes[hullName];
		setPropulsor(man, propName);
	}

	void updateKinematics(ref const KinematicSnapshot snap)
	{
		trace.appendSnapshot(snap);
	}

	/// returns true if the snapshot was written to res
	bool getLastSnapshot(out KinematicSnapshot res) const
	{
		if (trace.canInterpolate)
		{
			res = trace.mostRecent;
			return true;
		}
		return false;
	}

	/// returns true if the snapshot was written to res
	bool getInterpolatedSnapshot(out KinematicSnapshot res) const
	{
		if (trace.canInterpolate)
		{
			res = trace.result;
			return true;
		}
		return false;
	}

	override void update(CameraContext camCtx, long usecsDelta)
	{
		if (trace.canInterpolate)
		{
			trace.moveForward(usecsDelta);
			// update transform from the trace
			transform.position = trace.result.position;
			transform.rotation = trace.result.rotation;
		}
		foreach (prop; m_propulsors)
			prop.update(camCtx, usecsDelta);
	}

	override void render(Window wnd)
	{
		foreach (prop; m_propulsors)
			prop.renderBack(wnd);
		for (int i = 0; i < m_tmpl.elevatedHullShapeIdx; i++)
			m_shapes[i].render(wnd, transform.world);
		foreach (prop; m_propulsors)
			prop.renderFront(wnd);
		for (int i = m_tmpl.elevatedHullShapeIdx; i < m_shapes.length; i++)
			m_shapes[i].render(wnd, transform.world);
	}

	/// Remove existing propulsor and set a new one
	void setPropulsor(EntityManager man, string propName)
	{
		// unset existing propulsors
		foreach (p; m_propulsors)
			transform.removeChild(p.transform);
		m_propulsors.length = 0;
		// setup propulsors
		foreach (mount; m_tmpl.propulsionMounts)
		{
			Propulsor p = createPropulsor(man, propName);
			p.transform.scale = vec2d(mount.scale, mount.scale);
			p.transform.rotation = mount.rotation;
			p.transform.position = mount.mountCenter.tod;
			transform.addChild(p.transform);
			m_propulsors ~= p;
		}
	}
}


/// Collection of shapes and templates, created from the entity database
final class EntityManager
{
	private ConvexShape[string] m_propulsorShapes;
	private ConvexShape[][string] m_submarineShapes;

	mixin Readonly!(const(PropulsorTemplate)*[string], "propTemplates");
	mixin Readonly!(const(SubmarineTemplate)*[string], "submarineTemplates");

	/// construct shape collection from entity database
	this(const(EntityDbRes) db)
	{
		info("building entity manager from serialized database");
		foreach (prop; db.propulsors)
		{
			auto ptr = new PropulsorTemplate;
			*ptr = cast(PropulsorTemplate) prop;
			m_propTemplates[prop.name] = ptr;
			m_propulsorShapes[prop.name] = fromPolygon(prop.model);
		}
		foreach (sub; db.controllableSubs)
		{
			auto ptr = new SubmarineTemplate;
			*ptr = cast(SubmarineTemplate) sub;
			m_submarineTemplates[sub.name] = ptr;
			m_submarineShapes[sub.name] =
				sub.hullModel.map!(a => fromPolygon(a)).array;
		}
	}

	private ConvexShape fromPolygon(const(ConvexPolygon) p)
	{
		return new ConvexShape(
			cast(const(sfVector2f)[]) p.points,
			cast(sfColor) p.fillColor,
			cast(sfColor) p.borderColor,
			p.borderWidth);
	}
}
