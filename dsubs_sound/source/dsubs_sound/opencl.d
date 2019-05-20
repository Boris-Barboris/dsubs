module dsubs_sound.opencl;

import std.algorithm.mutation: swap;
import std.traits: isPointer;
import std.string: toStringz;
import std.parallelism: totalCPUs;

import derelict.opencl.cl;

import dsubs_common.utils;

import dsubs_sound.common;
import dsubs_sound.fft;
import dsubs_sound.spectrum;
import dsubs_sound.activesonar;
import dsubs_sound.water;
import dsubs_sound.filter;


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
	if (platformCount == 0)
		throw new Exception("Install OpenCL! 'ocl-icd' and vendor drivers for example.");
	cl_platform_id[] ids = new cl_platform_id[platformCount];
	clGetPlatformIDs(platformCount, ids.ptr, &platformCount).clError;
	Platform[] platformList;
	foreach (idx, i; ids)
	{
		Platform p = getPlatformById(i);
		trace("found platform: ", p, (idx == ids.length - 1) ? " (selected)" : "");
		platformList ~= p;
	}
	DerelictCL.reload(CLVersion.CL12);
	return platformList[$-1];
}


/// Monochrome single-channel image
struct Image(T)
	if (is(T == ubyte) || is(T == float))
{

	alias type = T;

	this(DsubsSoundOpenclCtx ctx, size_t width, size_t height,
		cl_mem_flags flags = CL_MEM_READ_WRITE)
	{
		static if (is(T == float))
			enum channel_type = CL_FLOAT;
		else
			enum channel_type = CL_UNORM_INT8;
		cl_image_format imgFormat = cl_image_format(CL_R, channel_type);
		cl_image_desc desc = cl_image_desc(
			 CL_MEM_OBJECT_IMAGE2D, width, height, 1, 1, 0, 0, 0, 0, null);
		m_width = width;
		m_height = height;
		cl_int err;
		m_mem = clCreateImage(ctx.m_ctx, flags, &imgFormat, &desc, null, &err);
		err.clError();
	}

	@disable this(this);

	~this()
	{
		release();
	}

	void release() nothrow @nogc
	{
		if (!m_released)
		{
			if (m_mem != cl_mem.init)
				clReleaseMemObject(m_mem);
			m_released = true;
		}
	}

	private
	{
		bool m_released;
		size_t m_width, m_height;
		cl_mem m_mem;
	}

	@property size_t w() const { return m_width; }
	@property size_t h() const { return m_height; }

	/// buffer data size in bytes
	@property size_t size() const { return m_width * m_height * T.sizeof; }

	package @property const(cl_mem)* mem() const { return &m_mem; }

package:

	AsyncEvent enqueueRead(CommandQueue q, T[] dest,
		size_t[2] origin, size_t[2] region)
	{
		assert(dest.length == region[0] * region[1]);
		AsyncEvent res;
		size_t[3] corigin = [origin[0], origin[1], 0];
		size_t[3] cregion = [region[0], region[1], 1];
		clEnqueueReadImage(q.m_q, m_mem, false, &corigin[0], &cregion[0],
			0, 0, dest.ptr, 0, null, &res.cl).clError();
		return res;
	}
}

alias FloatImage = Image!float;
alias ByteImage = Image!ubyte;


struct Buffer
{
	this(CommandQueue q, const void[] data,
		cl_mem_flags flags = CL_MEM_READ_WRITE)
	{
		cl_int err;
		m_size = data.length;
		m_mem = clCreateBuffer(q.m_ctx.m_ctx, flags, m_size, null, &err);
		err.clError();
		//trace("new buffer pointer ", m_mem);
		scope(failure) release();
		clEnqueueWriteBuffer(q.m_q, m_mem, true, 0, m_size, data.ptr, 0,
			null, null).clError;
	}

	this(DsubsSoundOpenclCtx ctx, size_t size,
		cl_mem_flags flags = CL_MEM_READ_WRITE)
	{
		cl_int err;
		m_size = size;
		m_mem = clCreateBuffer(ctx.m_ctx, flags, m_size, null, &err);
		//trace("new buffer pointer ", m_mem);
		err.clError();
	}

	@disable this(this);

	~this()
	{
		release();
	}

	void swapWith(ref Buffer rhs)
	{
		assert(m_size == rhs.m_size);
		swap(m_mem, rhs.m_mem);
		swap(m_released, rhs.m_released);
	}

	void release() nothrow @nogc
	{
		import core.stdc.stdio;
		if (!m_released)
		{
			if (m_mem != cl_mem.init)
			{
				//printf("releasing buffer %p\n", m_mem);
				clReleaseMemObject(m_mem);
			}
			m_released = true;
		}
	}

	private
	{
		bool m_released;
		size_t m_size;
		cl_mem m_mem;
	}

	package @property const(cl_mem)* mem() const { return &m_mem; }

	/// buffer data size in bytes
	@property size_t size() const { return m_size; }


package:

	AsyncEvent enqueueCopy(CommandQueue q, ref Buffer dest, const(AsyncEvent)* onlyAfter)
	{
		assert(m_mem !is cl_mem.init);
		assert(dest.m_size == m_size);
		AsyncEvent evt;
		if (onlyAfter is null)
		{
			clEnqueueCopyBuffer(q.m_q, m_mem, dest.m_mem, 0, 0, m_size, 0,
				null, &evt.cl).clError;
		}
		else
		{
			clEnqueueCopyBuffer(q.m_q, m_mem, dest.m_mem, 0, 0, m_size, 1,
				&onlyAfter.cl, &evt.cl).clError;
		}
		return evt;
	}

	AsyncEvent enqueueCopy(CommandQueue q, ref Buffer dest, size_t srcOffset,
		size_t destOffset, size_t count, const(AsyncEvent)* onlyAfter)
	{
		assert(m_mem !is cl_mem.init);
		assert(dest.m_size >= count);
		assert(m_size >= count);
		AsyncEvent evt;
		if (onlyAfter is null)
		{
			clEnqueueCopyBuffer(q.m_q, m_mem, dest.m_mem, srcOffset, destOffset, count, 0,
				null, &evt.cl).clError;
		}
		else
		{
			clEnqueueCopyBuffer(q.m_q, m_mem, dest.m_mem, srcOffset, destOffset, count, 1,
				&onlyAfter.cl, &evt.cl).clError;
		}
		return evt;
	}

	AsyncEvent enqueueFullFill(T)(CommandQueue q, const T val, const(AsyncEvent)* onlyAfter)
	{
		assert(m_mem !is cl_mem.init);
		AsyncEvent evt;
		if (onlyAfter is null)
		{
			clEnqueueFillBuffer(q.m_q, m_mem, &val, T.sizeof, 0, m_size,
				0, null, &evt.cl).clError;
		}
		else
		{
			clEnqueueFillBuffer(q.m_q, m_mem, &val, T.sizeof, 0, m_size,
				1, &onlyAfter.cl, &evt.cl).clError;
		}
		return evt;
	}

	AsyncEvent enqueueFill(T)(CommandQueue q, const T val, size_t offset, size_t count,
		const(AsyncEvent)* onlyAfter)
	{
		assert(m_mem !is cl_mem.init);
		AsyncEvent evt;
		if (onlyAfter is null)
		{
			clEnqueueFillBuffer(q.m_q, m_mem, &val, T.sizeof, offset * T.sizeof,
				count * T.sizeof, 0, null, &evt.cl).clError;
		}
		else
		{
			clEnqueueFillBuffer(q.m_q, m_mem, &val, T.sizeof, offset * T.sizeof,
				count * T.sizeof, 1, &onlyAfter.cl, &evt.cl).clError;
		}
		return evt;
	}

	AsyncEvent enqueueWrite(CommandQueue q, const void[] data, size_t offset, const(AsyncEvent)* onlyAfter)
	{
		assert(m_mem !is cl_mem.init);
		assert(data.length + offset <= m_size);
		AsyncEvent evt;
		if (onlyAfter is null)
		{
			clEnqueueWriteBuffer(q.m_q, m_mem, true, offset, data.length, data.ptr,
				0, null, &evt.cl).clError;
		}
		else
		{
			clEnqueueWriteBuffer(q.m_q, m_mem, true, offset, data.length, data.ptr,
				1, &onlyAfter.cl, &evt.cl).clError;
		}
		return evt;
	}

	AsyncEvent enqueueFullWrite(CommandQueue q, const void[] source, const(AsyncEvent)* onlyAfter)
	{
		assert(m_mem !is cl_mem.init);
		assert(source.length == m_size);
		AsyncEvent evt;
		if (onlyAfter is null)
		{
			clEnqueueWriteBuffer(q.m_q, m_mem, true, 0, m_size, source.ptr,
				0, null, &evt.cl).clError;
		}
		else
		{
			clEnqueueWriteBuffer(q.m_q, m_mem, true, 0, m_size, source.ptr,
				1, &onlyAfter.cl, &evt.cl).clError;
		}
		return evt;
	}

	/// asynchronous read
	AsyncEvent enqueueFullRead(CommandQueue q, void* dest, const(AsyncEvent)* onlyAfter)
	{
		assert(m_mem !is cl_mem.init);
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

	/// blocking read
	void fullRead(CommandQueue q, void* dest, const(AsyncEvent)* onlyAfter)
	{
		assert(m_mem !is cl_mem.init);
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
		if (err != CL_SUCCESS)
			error("clCreateProgramWithSource failed");
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
		{
			trace("clBuildProgram succeeded");
			err.clError();
		}
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

	/// Set size of __local kernel parameter
	void setLocalArgSize(cl_uint idx, const uint size)
	{
		clSetKernelArg(m_kern, idx, size, null).clError;
	}

	private
	{
		Program m_prog;
		cl_kernel m_kern;
	}

	void enqueue(CommandQueue q, cl_uint workDim, const size_t[] global_work_offset,
		const size_t[] global_work_size, const size_t[] local_work_size,
		const AsyncEvent* onlyAfter)
	{
		// AsyncEvent res;
		clEnqueueNDRangeKernel(q.m_q, m_kern, workDim,
			global_work_offset.ptr, global_work_size.ptr, local_work_size.ptr,
			onlyAfter is null ? 0 : 1,
			onlyAfter is null ? null : &onlyAfter.cl,
			null).clError;
		// return res;
	}

	void task(CommandQueue q, const AsyncEvent* onlyAfter)
	{
		// AsyncEvent res;
		clEnqueueTask(q.m_q, m_kern,
			onlyAfter is null ? 0 : 1,
			onlyAfter is null ? null : &onlyAfter.cl,
			null).clError;
		// return res;
	}
}


final class CommandQueue
{
	this(DsubsSoundOpenclCtx ctx, Program prog)
	{
		m_ctx = ctx;
		// CL_QUEUE_OUT_OF_ORDER_EXEC_MODE_ENABLE
		cl_int err;
		m_q = clCreateCommandQueue(ctx.m_ctx, ctx.m_dev, 0, &err);
		err.clError();

		// command queue acquires kernels
		mk_firTds = new Kernel(prog, "firTds");
		mk_radix2 = new Kernel(prog, "fftRadix2Kernel");
		mk_iradix2 = new Kernel(prog, "ifftRadix2Kernel");
		mk_radix4 = new Kernel(prog, "fftRadix4Kernel");
		mk_iradix4 = new Kernel(prog, "ifftRadix4Kernel");
		mk_uniformNoise = new Kernel(prog, "addUniformNoise");
		mk_energyToPressure = new Kernel(prog, "energyToPressure");
		mk_interpolateIntensity = new Kernel(prog, "interpolateIntensity");
		mk_interpolateIntensity2 = new Kernel(prog, "interpolateIntensity2");
		mk_modulateTrochoid = new Kernel(prog, "modulateTrochoid");
		mk_addTo = new Kernel(prog, "addTo");
		mk_toShortPcb = new Kernel(prog, "toShortPcb");
		mk_sumBuf = new Kernel(prog, "sumBuf");
		mk_generateSeaNoise = new Kernel(prog, "generateSeaNoise");
		mk_generateFlowNoise = new Kernel(prog, "generateFlowNoise");
		mk_propellerGenISpec = new Kernel(prog, "propellerGenISpec");
		mk_sonarReflectorPass = new Kernel(prog, "sonarReflectorPass");
		mk_sonarReverbPass = new Kernel(prog, "sonarReverbPass");
		mk_sonarIsotropicPass = new Kernel(prog, "sonarIsotropicPass");
		mk_sonarSlicePass = new Kernel(prog, "sonarSlicePass");

		// prepare queue-local fft engine
		fft = new FFTPlan!(GLOBAL_SRATE / 2)(ctx);

		s_tds = Tds(ctx);
		s_ispec = ISpectrum(ctx);
		s_ispec2 = ISpectrum(ctx);
		s_ilspec = ILevelSpectrum(ctx);
		s_pcbBuf = Buffer(ctx, GLOBAL_SRATE * short.sizeof);
		s_bandSumBuf = Buffer(ctx, float.sizeof);
	}

	private
	{
		cl_command_queue m_q;
		DsubsSoundOpenclCtx m_ctx;
	}

	/// Queue-local kernels and fft plan
	package
	{
		FFTPlan!(GLOBAL_SRATE / 2) fft;
		// kernels
		Kernel mk_firTds;
		Kernel mk_radix2;
		Kernel mk_iradix2;
		Kernel mk_radix4;
		Kernel mk_iradix4;
		Kernel mk_uniformNoise;
		Kernel mk_energyToPressure;
		Kernel mk_interpolateIntensity;
		Kernel mk_interpolateIntensity2;
		Kernel mk_modulateTrochoid;
		Kernel mk_addTo;
		Kernel mk_toShortPcb;
		Kernel mk_sumBuf;
		Kernel mk_generateSeaNoise;
		Kernel mk_generateFlowNoise;
		Kernel mk_propellerGenISpec;
		Kernel mk_sonarReflectorPass;
		Kernel mk_sonarReverbPass;
		Kernel mk_sonarIsotropicPass;
		Kernel mk_sonarSlicePass;
	}

	/// Queue-local shared buffers
	package
	{
		Tds s_tds;
		ISpectrum s_ispec;
		ISpectrum s_ispec2;
		ILevelSpectrum s_ilspec;
		Buffer s_bandSumBuf;	/// 4-byte buffer for one float
		/// short buffer for converted Tds
		Buffer s_pcbBuf;
	}

	/// Context this queue belongs to
	@property DsubsSoundOpenclCtx ctx() { return m_ctx; }

	~this()
	{
		release();
	}

	private void release() @nogc nothrow
	{
		if (m_q !is cl_command_queue.init)
		{
			clReleaseCommandQueue(m_q);
			m_q = cl_command_queue.init;
		}
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

		// global stuff
		LinearFilter*[string] m_filters;
	}

	/// pre-built high-pass filter 500Hz+
	package LinearFilter* getFilter(string name) { return m_filters[name]; }

	package
	{
		Buffer b_wrdks;
		PingTdsCache pingTds;
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
		trace("OpenCL context successfully created, compiling kernels");
		// import("pyopencl-complex.h")
		m_prog = new Program(this, import("kernel.c"));
		trace("kernels compiled, preparing command queues");
		m_queues.length = queueCount;
		for (int i = 0; i < queueCount; i++)
			m_queues[i] = new CommandQueue(this, m_prog);
		trace("OpenCL kernels loaded, preparing filters");
		m_filters["octaveHp250"] = new LinearFilter(queue(0), octaveHp250);
		m_queues[0].finish();
		trace("Filters loaded");
		b_wrdks = Buffer(queue(0), wrdk);
	}

	~this()
	{
		release(false);
	}

	private void release(bool releaseQueues = true) nothrow @nogc
	{
		if (!m_released)
		{
			clReleaseContext(m_ctx);
			if (releaseQueues)
			{
				foreach (cq; m_queues)
					cq.release();
			}
			m_released = true;
		}
	}

	CommandQueue queue(size_t queueIdx) { return m_queues[queueIdx]; }

	@property size_t queueCount() const { return m_queues.length; }
}


shared static this()
{
	initializeWrdk();
}


version (unittest)
{
	__gshared DsubsSoundOpenclCtx s_clCtx;

	shared static this()
	{
		try
		{
			s_clCtx = new DsubsSoundOpenclCtx();
		}
		catch (Exception ex)
		{
			error("Failed to create DsubsSoundOpenclCtx");
			error(ex.toString);
			throw ex;
		}
	}
}