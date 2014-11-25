#include <stdio.h>
#include <memory.h>

#include "cuda_helper.h"

#define ROTR(x,n) ROTR64(x,n)

#define USE_SHUFFLE 0

// die Message it Padding zur Berechnung auf der GPU
__constant__ uint64_t c_PaddedMessage80[16]; // padded message (80 bytes + padding)

// ---------------------------- BEGIN CUDA quark_blake512 functions ------------------------------------

__constant__ uint8_t c_sigma[16][16] =
{
	{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 },
	{ 14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3 },
	{ 11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4 },
	{ 7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8 },
	{ 9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13 },
	{ 2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9 },
	{ 12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11 },
	{ 13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10 },
	{ 6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5 },
	{ 10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0 },
	{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 },
	{ 14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3 },
	{ 11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4 },
	{ 7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8 },
	{ 9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13 },
	{ 2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9 }
};

__device__ __constant__
const uint64_t c_u512[16] =
{
  0x243f6a8885a308d3ULL, 0x13198a2e03707344ULL, 
  0xa4093822299f31d0ULL, 0x082efa98ec4e6c89ULL,
  0x452821e638d01377ULL, 0xbe5466cf34e90c6cULL, 
  0xc0ac29b7c97c50ddULL, 0x3f84d5b5b5470917ULL,
  0x9216d5d98979fb1bULL, 0xd1310ba698dfb5acULL, 
  0x2ffd72dbd01adfb7ULL, 0xb8e1afed6a267e96ULL,
  0xba7c9045f12c7f99ULL, 0x24a19947b3916cf7ULL, 
  0x0801f2e2858efc16ULL, 0x636920d871574e69ULL
};

#define G(a,b,c,d,x) { \
	uint8_t idx1 = c_sigma[i][x]; \
	uint8_t idx2 = c_sigma[i][x+1]; \
	v[a] += (m[idx1] ^ c_u512[idx2]) + v[b]; \
	v[d] = SWAPDWORDS( v[d] ^ v[a]); \
	v[c] += v[d]; \
	v[b] = ROTR( v[b] ^ v[c], 25); \
	v[a] += (m[idx2] ^ c_u512[idx1]) + v[b]; \
	v[d] = ROTR16( v[d] ^ v[a]); \
	v[c] += v[d]; \
	v[b] = ROTR( v[b] ^ v[c], 11); \
}

__device__ __forceinline__
void G3(uint64_t a, uint64_t b, uint64_t c, uint64_t d, const uint64_t x, uint64_t *m, uint64_t *v, int i)
{
	const uint32_t	idx1 = c_sigma[i][x];
	const uint32_t	idx2 = c_sigma[i][x + 1];
	const uint64_t const1 = m[idx1];
	const uint64_t const2 = c_u512[idx2];
	const uint64_t const3 = m[idx2];
	const uint64_t const4 = c_u512[idx1];

	uint64_t		t;
	uint2			t3, result;
	short4			temp;
	//	short4			t4;
	asm("xor.b64	%0, %1, %2;" : "=l"(t) : "l"(const1), "l"(const2));
	asm("add.s64 	%0, %1, %2;" : "=l"(v[a]) : "l"(v[a]), "l"(v[b]));
	asm("add.s64 	%0, %1, %2;" : "=l"(v[a]) : "l"(v[a]), "l"(t));
	asm("xor.b64 	%0, %1, %2;" : "=l"(t) : "l"(v[d]), "l"(v[a]));
	asm("mov.b64 	{%0, %1}, %2 ;" : "=r"(t3.x), "=r"(t3.y) : "l"(t));
	asm("mov.b64 	%0, {%1, %2} ;" : "=l"(v[d]) : "r"(t3.y), "r"(t3.x));
	asm("add.s64 	%0, %1, %2;" : "=l"(v[c]) : "l"(v[c]), "l"(v[d]));
	asm("xor.b64 	%0, %1, %2;" : "=l"(t) : "l"(v[b]), "l"(v[c]));
	asm("mov.b64 	{%0, %1}, %2 ;" : "=r"(t3.x), "=r"(t3.y) : "l"(t));
	asm("shf.r.wrap.b32 %0, %1, %2, 25;" : "=r"(result.x) : "r"(t3.y), "r"(t3.x));
	asm("shf.r.wrap.b32 %0, %1, %2, 25;" : "=r"(result.y) : "r"(t3.x), "r"(t3.y));
	asm("mov.b64 	%0, {%1, %2} ;" : "=l"(v[b]) : "r"(result.y), "r"(result.x));
	asm("xor.b64 	%0, %1, %2;" : "=l"(t) : "l"(const3), "l"(const4));
	asm("add.s64 	%0, %1, %2;" : "=l"(t) : "l"(v[b]), "l"(t));
	asm("add.s64 	%0, %1, %2;" : "=l"(v[a]) : "l"(v[a]), "l"(t));
	asm("xor.b64  	%0, %1, %2;" : "=l"(v[d]) : "l"(v[d]), "l"(v[a]));
	asm("mov.b64 { %0,  %1, %2, %3 }, %4; ": "=h"(temp.x), "=h"(temp.y), "=h"(temp.z), "=h"(temp.w) : "l"(v[d]));
	asm("mov.b64 %0, {%1, %2, %3 , %4}; ":  "=l"(v[d]) : "h"(temp.y), "h"(temp.z), "h"(temp.w), "h"(temp.x));
	asm("add.s64 	%0, %1, %2;" : "=l"(v[c]) : "l"(v[c]), "l"(v[d]));
	asm("xor.b64  	%0, %1, %2;" : "=l"(v[b]) : "l"(v[b]), "l"(v[c]));
	asm("mov.b64 	{%0, %1}, %2 ;" : "=r"(t3.x), "=r"(t3.y) : "l"(v[b]));
	asm("shf.r.wrap.b32 %0, %1, %2, 11;" : "=r"(result.x) : "r"(t3.y), "r"(t3.x));
	asm("shf.r.wrap.b32 %0, %1, %2, 11;" : "=r"(result.y) : "r"(t3.x), "r"(t3.y));
	asm("mov.b64 	%0, {%1, %2} ;" : "=l"(v[b]) : "r"(result.y), "r"(result.x));
}

__device__ __forceinline__ 
void quark_blake512_compress(uint64_t *const __restrict__ h, const uint64_t *const __restrict__ block, const int T0)
{
	uint64_t v[16];
	uint64_t m[16];
	if (T0 == 640)
	{
#pragma unroll 16
		for (int i = 0; i < 16; i++) {
			m[i] = cuda_swab64(block[i]);
		}
	}

	#pragma unroll 8
	for (int i = 0; i < 8; i++)
		v[i] = h[i];
	v[ 8] = c_u512[0];
	v[ 9] = c_u512[1];
	v[10] = c_u512[2];
	v[11] = c_u512[3];
	v[12] = c_u512[4] ^ T0;
	v[13] = c_u512[5] ^ T0;
	v[14] = c_u512[6];
	v[15] = c_u512[7];

	//#pragma unroll 16
	for(int i = 0; i < 16; ++i )
	{

#if __CUDA_ARCH__ < 520
		G( 0, 4, 8, 12, 0 );
		G( 1, 5, 9, 13, 2 );
		G( 2, 6, 10, 14, 4 );
		G( 3, 7, 11, 15, 6 );
		G( 0, 5, 10, 15, 8 );
		G( 1, 6, 11, 12, 10 );
		G( 2, 7, 8, 13, 12 );
		G( 3, 4, 9, 14, 14 );
 #else
		G3(0, 4, 8, 12, 0,m,v,i);
		G3(1, 5, 9, 13, 2, m, v, i);
		G3(2, 6, 10, 14, 4, m, v, i);
		G3(3, 7, 11, 15, 6, m, v, i);
		G3(0, 5, 10, 15, 8, m, v, i);
		G3(1, 6, 11, 12, 10, m, v, i);
		G3(2, 7, 8, 13, 12, m, v, i);
		G3(3, 4, 9, 14, 14, m, v, i);
#endif
	}

	h[0] ^= v[0] ^ v[8];
	h[1] ^= v[1] ^ v[9];
	h[2] ^= v[2] ^ v[10];
	h[3] ^= v[3] ^ v[11];
	h[4] ^= v[4] ^ v[12];
	h[5] ^= v[5] ^ v[13];
	h[6] ^= v[6] ^ v[14];
	h[7] ^= v[7] ^ v[15];
}


// Hash-Padding
__device__ __constant__
static const uint64_t d_constHashPadding[8] = {
	0x0000000000000080ull,
	0,
	0,
	0,
	0,
	0x0100000000000000ull,
	0,
	0x0002000000000000ull
};

__global__ 
#if __CUDA_ARCH__ > 500
	__launch_bounds__(256, 2)
#else
	__launch_bounds__(256, 4)
#endif
void quark_blake512_gpu_hash_64(int threads, uint32_t startNounce, uint32_t *g_nonceVector, uint64_t *g_hash)
{
	int thread = (blockDim.x * blockIdx.x + threadIdx.x);

#if USE_SHUFFLE
	const int warpID = threadIdx.x & 0x0F; // 16 warps
	const int warpBlockID = (thread + 15)>>4; // aufrunden auf volle Warp-Bl�cke
	const int maxHashPosition = thread<<3;
#endif

#if USE_SHUFFLE
	if (warpBlockID < ( (threads+15)>>4 ))
#else
	if (thread < threads)
#endif
	{
		uint32_t nounce = (g_nonceVector != NULL) ? g_nonceVector[thread] : (startNounce + thread);

		int hashPosition = nounce - startNounce;
		uint64_t *inpHash = &g_hash[hashPosition<<3]; // hashPosition * 8

		// 128 Bytes
		uint64_t buf[16];

		// State
		uint64_t h[8] = {
			0x6a09e667f3bcc908ULL,
			0xbb67ae8584caa73bULL,
			0x3c6ef372fe94f82bULL,
			0xa54ff53a5f1d36f1ULL,
			0x510e527fade682d1ULL,
			0x9b05688c2b3e6c1fULL,
			0x1f83d9abfb41bd6bULL,
			0x5be0cd19137e2179ULL
		};

		// Message for first round
		#pragma unroll 8
		for (int i=0; i < 8; ++i)
			buf[i] = cuda_swab64(inpHash[i]);

		#pragma unroll 8
		for (int i=0; i < 8; i++)
			buf[i+8] = cuda_swab64(d_constHashPadding[i]);

		// Ending round
		quark_blake512_compress( h, buf, 512 );

#if __CUDA_ARCH__ <= 350
		uint32_t *outHash = (uint32_t*)&g_hash[8 * hashPosition];
		#pragma unroll 8
		for (int i=0; i < 8; i++) {
			outHash[2*i+0] = cuda_swab32( _HIWORD(h[i]) );
			outHash[2*i+1] = cuda_swab32( _LOWORD(h[i]) );
		}
#else
		uint64_t *outHash = &g_hash[8 * hashPosition];
		for (int i=0; i < 8; i++) {
			outHash[i] = cuda_swab64(h[i]);
		}
#endif
	}
}

__global__ 
#if __CUDA_ARCH__ > 500
__launch_bounds__(256, 2)
#else
__launch_bounds__(256, 4)
#endif
void quark_blake512_gpu_hash_80(int threads, uint32_t startNounce, uint32_t *outputHash)
{
	int thread = (blockDim.x * blockIdx.x + threadIdx.x);
	if (thread < threads)
	{
		uint64_t buf[16];
		uint32_t nounce = startNounce + thread;

		uint64_t h[8] = {
			0x6a09e667f3bcc908ULL,
			0xbb67ae8584caa73bULL,
			0x3c6ef372fe94f82bULL,
			0xa54ff53a5f1d36f1ULL,
			0x510e527fade682d1ULL,
			0x9b05688c2b3e6c1fULL,
			0x1f83d9abfb41bd6bULL,
			0x5be0cd19137e2179ULL
		};

		// Message f�r die erste Runde in Register holen
		#pragma unroll 16
		for (int i=0; i < 16; ++i)
			buf[i] = c_PaddedMessage80[i];

		// The test Nonce
		((uint32_t*)buf)[19] = cuda_swab32(nounce);

		quark_blake512_compress( h, buf, 640 );

#if __CUDA_ARCH__ <= 350
		uint32_t *outHash = outputHash + 16 * thread;
		#pragma unroll 8
		for (uint32_t i=0; i < 8; i++) {
			outHash[2*i]   = cuda_swab32( _HIWORD(h[i]) );
			outHash[2*i+1] = cuda_swab32( _LOWORD(h[i]) );
		}
#else
		uint64_t *outHash = (uint64_t *)outputHash + 8 * thread;
		for (uint32_t i=0; i < 8; i++) {
			outHash[i] = cuda_swab64( h[i] );
		}
#endif

	}
}


// ---------------------------- END CUDA quark_blake512 functions ------------------------------------


// Blake512 f�r 80 Byte grosse Eingangsdaten
__host__ void quark_blake512_cpu_setBlock_80(void *pdata)
{
	// Message mit Padding bereitstellen
	// lediglich die korrekte Nonce ist noch ab Byte 76 einzusetzen.
	unsigned char PaddedMessage[128];
	memcpy(PaddedMessage, pdata, 80);
	memset(PaddedMessage+80, 0, 48);
	PaddedMessage[80] = 0x80;
	PaddedMessage[111] = 1;
	PaddedMessage[126] = 0x02;
	PaddedMessage[127] = 0x80;

	CUDA_SAFE_CALL(
		cudaMemcpyToSymbol(c_PaddedMessage80, PaddedMessage, 16*sizeof(uint64_t), 0, cudaMemcpyHostToDevice)
	);
}


__host__ void quark_blake512_cpu_hash_64(int thr_id, int threads, uint32_t startNounce, uint32_t *d_nonceVector, uint32_t *d_outputHash, int order)
{
	const int threadsperblock = 256;
	// berechne wie viele Thread Blocks wir brauchen
	dim3 grid((threads + threadsperblock-1)/threadsperblock);
	dim3 block(threadsperblock);

	// Gr��e des dynamischen Shared Memory Bereichs
	size_t shared_size = 0;

	quark_blake512_gpu_hash_64<<<grid, block, shared_size>>>(threads, startNounce, d_nonceVector, (uint64_t*)d_outputHash);

	// Strategisches Sleep Kommando zur Senkung der CPU Last
	MyStreamSynchronize(NULL, order, thr_id);
}

__host__ void quark_blake512_cpu_hash_80(int thr_id, int threads, uint32_t startNounce, uint32_t *d_outputHash, int order)
{
	const int threadsperblock = 256;
	// berechne wie viele Thread Blocks wir brauchen
	dim3 grid((threads + threadsperblock-1)/threadsperblock);
	dim3 block(threadsperblock);

	// Gr��e des dynamischen Shared Memory Bereichs
	size_t shared_size = 0;

	quark_blake512_gpu_hash_80<<<grid, block, shared_size>>>(threads, startNounce, d_outputHash);

	// Strategisches Sleep Kommando zur Senkung der CPU Last
	MyStreamSynchronize(NULL, order, thr_id);
}
