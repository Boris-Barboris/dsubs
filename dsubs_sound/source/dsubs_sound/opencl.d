module dsubs_sound.opencl;

import std.experimental.logger: trace;
import std.traits: isPointer;
import std.string: toStringz;
import std.parallelism: totalCPUs;

import derelict.opencl.cl;

import dsubs_common.utils;
import dsubs_sound.common;


class OpenCLException: Exception
{
	mixin ExceptionConstructors;
}

/// Handle to asynchronous event completion
struct AsyncEvent
{
	cl_event cl;
}

void release(AsyncEvent evt)
{
	clReleaseEvent(evt.cl);
}

/// wait for and release event
void waitFor(AsyncEvent evt)
{
	clWaitForEvents(1, &evt.cl).clError();
	cl_int execStatus;
	clGetEventInfo(evt.cl, CL_EVENT_COMMAND_EXECUTION_STATUS,
		cl_int.sizeof, &execStatus, null).clError;
	release(evt);
	if (execStatus != CL_COMPLETE)
		throw new OpenCLException("command failed with code " ~ execStatus.to!string);
}

void clError(cl_int err)
{
	if (err != CL_SUCCESS)
		throw new OpenCLException("Opencl error code " ~ err.to!string);
}

private struct Platform
{
	cl_platform_id id;
	string name;
	string vers;
}

private Platform getPlatformById(cl_platform_id id)
{
	Platform res = Platform(id);
	char[] name = new char[64];
	size_t actual_len;
	clGetPlatformInfo(id, CL_PLATFORM_NAME, 64, name.ptr, &actual_len).clError;
	name.length = actual_len;
	res.name = cast(string) name;
	char[] vers = new char[64];
	clGetPlatformInfo(id, CL_PLATFORM_VERSION, 64, vers.ptr, &actual_len).clError;
	vers.length = actual_len;
	res.vers = cast(string) vers;
	return res;
}

/// Try load opencl libraries and choose platform
private Platform loadOpenclLibrary()
{
	trace("Loading OpenCL shared libraries");
	DerelictCL.load();
	trace("OK. Loaded ", DerelictCL.loadedVersion());
	uint platformCount = 0;
	clGetPlatformIDs(0, null, &platformCount).clError;
	trace("detected ", platformCount, " OpenCL platform(s)");
	cl_platform_id[] ids = new cl_platform_id[platformCount];
	clGetPlatformIDs(platformCount, ids.ptr, &platformCount).clError;
	Platform[] platformList;
	foreach (i; ids)
	{
		Platform p = getPlatformById(i);
		trace("found platform: ", p);
		platformList ~= p;
	}
	DerelictCL.reload(CLVersion.CL12);
	return platformList[0];
}


class Buffer
{
	this(CommandQueue q, void[] data,
		cl_mem_flags flags = CL_MEM_READ_WRITE)
	{
		m_ctx = q.m_ctx;
		cl_int err;
		m_size = data.length;
		m_mem = clCreateBuffer(m_ctx.m_ctx, flags, m_size, null, &err);
		err.clError();
		scope(failure) release();
		clEnqueueWriteBuffer(q.m_q, m_mem, true, 0, m_size, data.ptr, 0,
			null, null).clError;
	}

	this(DsubsSoundOpenclCtx ctx, size_t size,
		cl_mem_flags flags = CL_MEM_READ_WRITE)
	{
		m_ctx = ctx;
		cl_int err;
		m_size = size;
		m_mem = clCreateBuffer(ctx.m_ctx, flags, m_size, null, &err);
		err.clError();
	}

	~this()
	{
		release();
	}

	void release() nothrow @nogc
	{
		if (!m_released)
		{
			clReleaseMemObject(m_mem);
			m_released = true;
		}
	}

	private
	{
		bool m_released;
		size_t m_size;
		DsubsSoundOpenclCtx m_ctx;
		cl_mem m_mem;
	}

	/// buffer data size in bytes
	final @property size_t size() const { return m_size; }


protected final:

	AsyncEvent enqueueFullWrite(CommandQueue q, void[] source, const(AsyncEvent)* onlyAfter)
	{
		assert(source.length == m_size);
		AsyncEvent evt;
		if (onlyAfter is null)
		{
			clEnqueueWriteBuffer(q.m_q, m_mem, false, 0, m_size, source.ptr,
				0, null, &evt.cl).clError;
		}
		else
		{
			clEnqueueWriteBuffer(q.m_q, m_mem, false, 0, m_size, source.ptr,
				1, &onlyAfter.cl, &evt.cl).clError;
		}
		return evt;
	}

	void fullWrite(CommandQueue q, void[] source, const(AsyncEvent)* onlyAfter)
	{
		assert(source.length == m_size);
		if (onlyAfter is null)
		{
			clEnqueueWriteBuffer(q.m_q, m_mem, true, 0, m_size, source.ptr,
				0, null, null).clError;
		}
		else
		{
			clEnqueueWriteBuffer(q.m_q, m_mem, true, 0, m_size, source.ptr,
				1, &onlyAfter.cl, null).clError;
		}
	}

	AsyncEvent enqueueFullRead(CommandQueue q, void* dest, const(AsyncEvent)* onlyAfter)
	{
		AsyncEvent evt;
		if (onlyAfter is null)
			clEnqueueReadBuffer(q.m_q, m_mem, false, 0, m_size, dest, 0, null, &evt.cl).clError;
		else
		{
			clEnqueueReadBuffer(q.m_q, m_mem, false, 0, m_size, dest,
				1, &onlyAfter.cl, &evt.cl).clError;
		}
		return evt;
	}

	void fullRead(CommandQueue q, void* dest, const(AsyncEvent)* onlyAfter)
	{
		if (onlyAfter is null)
		{
			clEnqueueReadBuffer(q.m_q, m_mem, true, 0, m_size, dest,
				0, null, null).clError;
		}
		else
		{
			clEnqueueReadBuffer(q.m_q, m_mem, true, 0, m_size, dest,
				1, &onlyAfter.cl, null).clError;
		}
	}
}


private final class Program
{
	this(DsubsSoundOpenclCtx ctx, string source)
	{
		m_ctx = ctx;
		cl_int err;
		auto ptr = source.ptr;
		m_prog = clCreateProgramWithSource(ctx.m_ctx, 1, &ptr,
			[source.length].ptr, &err);
		err.clError();
		err = clBuildProgram(m_prog, 0, null, "-cl-std=CL1.2 -Werror".toStringz, null, null);
		if (err == CL_BUILD_PROGRAM_FAILURE)
		{
			size_t len = 0;
			clGetProgramBuildInfo(m_prog, m_ctx.m_dev, CL_PROGRAM_BUILD_LOG,
				0, null, &len).clError;
			char[] msg = new char[len];
			clGetProgramBuildInfo(m_prog, m_ctx.m_dev, CL_PROGRAM_BUILD_LOG,
				len, msg.ptr, null).clError;
			throw new OpenCLException(cast(string) msg);
		}
		else
			err.clError();
	}

	~this()
	{
		clReleaseProgram(m_prog);
	}

	DsubsSoundOpenclCtx m_ctx;
	cl_program m_prog;
}


final class Kernel
{
	this(Program prog, string name)
	{
		m_prog = prog;
		cl_int err;
		m_kern = clCreateKernel(prog.m_prog, name.toStringz, &err);
		err.clError();
	}

	~this()
	{
		clReleaseKernel(m_kern);
	}

	void setArg(T)(cl_uint idx, const(T)* arg)
	{
		clSetKernelArg(m_kern, idx, T.sizeof, arg).clError;
	}

	void setArg(T)(cl_uint idx, const T arg)
		if (!isPointer!T)
	{
		clSetKernelArg(m_kern, idx, T.sizeof, &arg).clError;
	}

	private
	{
		Program m_prog;
		cl_kernel m_kern;
	}

	AsyncEvent enqueue(CommandQueue q, cl_uint workDim, const size_t[] global_work_offset,
		const size_t[] global_work_size, const size_t[] local_work_size,
		const AsyncEvent* onlyAfter)
	{
		AsyncEvent res;
		clEnqueueNDRangeKernel(q.m_q, m_kern, workDim,
			global_work_offset.ptr, global_work_size.ptr, local_work_size.ptr,
			onlyAfter is null ? 0 : 1,
			onlyAfter is null ? null : &onlyAfter.cl,
			&res.cl).clError;
		return res;
	}
}


final class CommandQueue
{
	this(DsubsSoundOpenclCtx ctx)
	{
		m_ctx = ctx;
		// CL_QUEUE_OUT_OF_ORDER_EXEC_MODE_ENABLE
		cl_int err;
		m_q = clCreateCommandQueue(ctx.m_ctx, ctx.m_dev, 0, &err);
		err.clError();
	}

	private
	{
		cl_command_queue m_q;
		DsubsSoundOpenclCtx m_ctx;
	}

	~this()
	{
		release();
	}

	void release() @nogc nothrow
	{
		if (m_q !is cl_command_queue.init)
			clReleaseCommandQueue(m_q);
	}

	AsyncEvent insertMarker()
	{
		AsyncEvent res;
		clEnqueueMarker(m_q, &res.cl).clError;
		return res;
	}

	/// block until all commands in queue succeeded
	void finish()
	{
		clFinish(m_q).clError;
	}
}


final class DsubsSoundOpenclCtx
{
	private
	{
		Platform m_plat;
		cl_context m_ctx;
		/// device of this context
		cl_device_id m_dev;
		bool m_released;
		Program m_prog;
		CommandQueue[] m_queues;

		// precompiled kernels
		Kernel mk_firTds;
	}

	package @property
	{
		Kernel firTds() { return mk_firTds; }
	}

	this(int queueCount = totalCPUs)
	{
		m_plat = loadOpenclLibrary();
		cl_context_properties[] ctx_props;
		ctx_props ~= cast(cl_context_properties) CL_CONTEXT_PLATFORM;
		ctx_props ~= cast(cl_context_properties) m_plat.id;
		ctx_props ~= cast(cl_context_properties) 0;
		cl_int err;
		m_ctx = clCreateContextFromType(ctx_props.ptr, CL_DEVICE_TYPE_DEFAULT,
			null, null, &err);
		err.clError();
		scope(failure) release();
		clGetContextInfo(m_ctx, CL_CONTEXT_DEVICES, m_dev.sizeof, &m_dev, null).clError;
		m_queues.length = queueCount;
		for (int i = 0; i < queueCount; i++)
			m_queues[i] = new CommandQueue(this);
		trace("OpenCL context successfully created, compiling kernels");
		m_prog = new Program(this, import("pyopencl-complex.h") ~ import("kernel.c"));
		mk_firTds = new Kernel(m_prog, "firTds");
		trace("OpenCL kernels loaded");
	}

	~this()
	{
		release();
	}

	void release() nothrow @nogc
	{
		if (!m_released)
		{
			clReleaseContext(m_ctx);
			foreach (cq; m_queues)
				cq.release();
			m_released = true;
		}
	}

	CommandQueue queue(size_t queueIdx) { return m_queues[queueIdx]; }

	@property size_t queueCount() const { return m_queues.length; }
}


version (unittest)
{
	__gshared DsubsSoundOpenclCtx s_clCtx;

	shared static this()
	{
		s_clCtx = new DsubsSoundOpenclCtx();
	}
}

unittest
{
	import std.stdio;
	import std.range: chain;
	import core.time: MonoTime;
	import dsubs_sound.filter;
	import dsubs_sound.wav;

	DsubsSoundOpenclCtx ctx = s_clCtx;
	Kernel filtKern = ctx.firTds;

	float[] prevSource = new float[4096 * 5];
	float[] curSource = new float[4096 * 5];
	for (int i = 0; i < prevSource.length; i++)
	{
		prevSource[i] = uniform(-1.0f, 1.0f);
		curSource[i] = uniform(-1.0f, 1.0f);
	}

	CommandQueue mainQueue = ctx.queue(0);
	struct FiltrationCtx
	{
		Buffer prevTds, curTds, dest, filterTaps;
	}
	FiltrationCtx[] expCtxs = new FiltrationCtx[ctx.queueCount];
	foreach (ref exp; expCtxs)
	{
		exp.prevTds = new Buffer(mainQueue, prevSource, CL_MEM_READ_ONLY);
		exp.curTds = new Buffer(mainQueue, curSource, CL_MEM_READ_ONLY);
		exp.dest = new Buffer(ctx, 4096 * 5 * float.sizeof, CL_MEM_WRITE_ONLY);
		exp.filterTaps = new Buffer(mainQueue, cast(float[]) octaveHp500, CL_MEM_READ_ONLY);
	}
	mainQueue.finish();

	auto startAt = MonoTime.currTime();
	int filtCount = 256;
	for (int i = 0; i < filtCount; i++)
	{
		FiltrationCtx exp = expCtxs[i % ctx.queueCount];
		filtKern.setArg(0, &exp.prevTds.m_mem);
		filtKern.setArg(1, &exp.curTds.m_mem);
		filtKern.setArg(2, &exp.filterTaps.m_mem);
		filtKern.setArg(3, octaveHp500.length.to!int);
		filtKern.setArg(4, &exp.dest.m_mem);
		CommandQueue q = ctx.queue(i % ctx.queueCount);
		filtKern.enqueue(q, 1, null, [4096 * 5], null, null).release();
	}
	for (int i = 0; i < ctx.queueCount; i++)
		ctx.queue(i).finish();
	writeln(filtCount, " FIR passes took ", MonoTime.currTime - startAt, " on ",
		ctx.queueCount, " OpenCL queues");

	expCtxs[0].dest.fullRead(mainQueue, prevSource.ptr, null);
	writeWavFile("opencl_filter.wav", chain(curSource, prevSource), 0.7f, 4096);
}
