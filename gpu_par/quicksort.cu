#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "common/io.h"
#include <time.h>
#include <cuda.h>
//#include "common/cuPrintf.cu"

/*********************** Data Definitions ********************************/
#define THREADS_PER_BLOCK 128

//These Inline Functions are used in the CPU Quicksort Implementation
#define swap(A,B) { float temp = A; A = B; B = temp;}
//#define compswap(A,B) if(B < A) swap(A,B)

//These Data Structs are used in the GPU Quicksort Implementation

typedef struct vars{
  int l;
  int r;
  int leq;
} vars;

/*********************** CPU QUICKSORT IMPLEMENTATION ***********************/

/* csort
 *
 * This function is an implementation of 'Quicksort with three-way 
 * partitioning' from 'Algorithms in C' (Program 7.5, page 326).
 *
 * Parameters:
 * ls: The list of floating points being sorted
 * l: index of the left most item in ls being sorted at the moment
 * r: index of the right most item in ls being sorted at the moment
 */
void csort(float ls[], int l, int r){
  int i, j, k, p, q;
  float v;
  if(r <= l)
    return;
  v = ls[r];
  i = l-1;
  j = r;
  p = l-1;
  q = r;
  for(;;){
    while(ls[++i] < v);
    while(v < ls[--j])
      if(j == l)
	break;
    if(i >= j)
      break;
    swap(ls[i],ls[j]);
    if(ls[i] == v){
      p++;
      swap(ls[p], ls[i]);
    }
    if(v == ls[j]){
      q--;
      swap(ls[q],ls[j]);
    }
  }
  swap(ls[i],ls[r]);
  j = i-1;
  i++;
  for(k = l; k < p; k++,j--)
    swap(ls[k],ls[j]);
  for(k = r-1; k > q; k--,i++)
    swap(ls[k], ls[i]);

  csort(ls, l, j);
  csort(ls, i, r);
}

/* cpu_quicksort
 *
 * This function is called to sort the floating point array using a CPU-based
 * implementation of quicksort. Its purpose is to set up the timing functions
 * to wrap the recursive 'csort' function which does the actual sorting
 *
 * Parameters:
 * unsorted: The array of floating point numbers to be sorted
 * length: the length of the unsorted & sorted arrays
 * sorted: an output parameter, will store the final, sorted array.
 *
 * Output:
 * time: This function should return the amount of time taken to sort the list.
 */
double cpu_quicksort(float unsorted[], int length, float sorted[]){

  for(int i = 0; i < length; i++)
    sorted[i] = unsorted[i];

  clock_t start, end;
  double time;
  start = clock();
  csort(sorted, 0, length - 1);
  end = clock();
  time = ((double) end - start) / CLOCKS_PER_SEC;

  return time;
}

/***************************** GPU IMPLEMENTATION ****************************/

/* gpuPartitionSwap
 *
 * This kernel function is called recursively by the host. Its purpose is to, 
 * given a pivot value, partition and swap items in the section of the input
 * array bounded by the l & r indices, then store the pivot in the correct
 * location.
 *
 * Parameters:
 * input: The unsorted (or partially sorted) input data
 * output: The aptly named output parameter, it is the same as input, but all
 *         floating points within (l,r) have been partitioned and swapped.
 * endpts: This is a custom data struct meant to 
 *         a) hold a counter variable in global memory
 *         b) pass the l' and r' parameters back to the host to the left and
 *            right of the positioned pivot item.
 * pivot: This is the pivot value, about which all items in (l,r) are being
 *        swapped.
 * l: the left index bound on input & output
 * r: the right index bound on input & output
 * d_leq: an array of offset values, storedin global device memory
 * nBlocks: The total number of blocks, to be used to determine the location
 *          of insertion of the pivot.
 *
 */
__global__ void gpuPartitionSwap(float * input, float * output, vars * endpts, 
				 float pivot, int l, int r, int d_leq[], 
				 int d_gt[], int nBlocks)
{
  //copy a section of the input into shared memory
  __shared__ float bInput[THREADS_PER_BLOCK];
  __syncthreads();
  int idx = l + blockIdx.x*THREADS_PER_BLOCK + threadIdx.x;

  if(threadIdx.x == 0){
    d_leq[blockIdx.x] = 0;
    d_gt[blockIdx.x] = 0;
  }
  __syncthreads();

  if(idx <= (r - 1)){
    bInput[threadIdx.x] = input[idx];

    //make comparison against the pivot, setting 'status' and updating the counter (if necessary)
    if( bInput[threadIdx.x] <= pivot ){
      atomicAdd( &(d_leq[blockIdx.x]), 1);
    } else {
      atomicAdd( &(d_gt[blockIdx.x]), 1);
    }
    
  }
  __syncthreads();

  if(threadIdx.x == 0){
    int lOffset = l;
    int rOffset = r;
    for(int i = 1; i <= blockIdx.x; i++){
      lOffset += d_leq[i - 1];
      rOffset -= d_gt[i - 1];
    }

    int m = 0;
    int n = 0;
    for(int j = 0; j < THREADS_PER_BLOCK; j++){
      int chk = l + blockIdx.x*THREADS_PER_BLOCK + j;
      if(chk <= (r-1) ){
	if(bInput[j] <= pivot){
	  output[lOffset + m] = bInput[j];
	  ++m;
	} else {
	  output[rOffset - n] = bInput[j];
	  ++n;
	}
      }
    }
  }

  __syncthreads();

  if((blockIdx.x == 0) && (threadIdx.x == 0)){
    int pOffset = l;
    for(int k = 0; k < nBlocks; k++)
      pOffset += d_leq[k];

    output[pOffset] = pivot;
    endpts->l = (pOffset - 1);
    endpts->r = (pOffset + 1);
  }

  return;
}

void gqSort(float ls[], int l, int r, int length){
  //if (r - l) >= 1
  if((r - l) >= 1){
    //1. grab pivot
    float pivot = ls[r];

    //2. set-up gpu vars
    int numBlocks = (r - l) / THREADS_PER_BLOCK;
    if((numBlocks * THREADS_PER_BLOCK) < (r - l))
      numBlocks++;

    float * d_ls;
    float * d_ls2;
    vars endpts;
    endpts.l = l;
    endpts.r = r;

    vars * d_endpts;
    int * d_leq, * d_gt;
    int size = sizeof(float);
    cudaMalloc(&(d_ls), size*length);
    cudaMalloc(&(d_ls2), size*length);
    cudaMalloc(&(d_endpts), sizeof(vars));
    cudaMalloc(&(d_leq), 4*numBlocks);
    cudaMalloc(&(d_gt), 4*numBlocks);
    cudaMemcpy(d_ls, ls, size*length, cudaMemcpyHostToDevice);
    cudaMemcpy(d_ls2, ls, size*length, cudaMemcpyHostToDevice);

    //3. call gpuPartition function
    gpuPartitionSwap<<<numBlocks, THREADS_PER_BLOCK>>>(d_ls, d_ls2, d_endpts, pivot, l, r, d_leq, d_gt, numBlocks);

    //4. Retrieve sorted list and other variables
    cudaMemcpy(ls, d_ls2, size*length, cudaMemcpyDeviceToHost);
    cudaMemcpy(&(endpts), d_endpts, sizeof(vars), cudaMemcpyDeviceToHost);

    cudaThreadSynchronize();
    cudaPrintfDisplay(stdout,true);
    //5.recursively call on left/right sections of list generated by gpuPartition

    if(endpts.l >= l)
      gqSort(ls, l, endpts.l, length);
    if(endpts.r <= r)
      gqSort(ls, endpts.r, r, length);
   
    cudaFree(d_ls);
    cudaFree(d_ls2);
    cudaFree(d_endpts);
    cudaFree(d_leq);
    cudaFree(d_gt);
  }

  return;
}

/* gpu_quicksort
 *
 * This is a function meant to set up the custom 'data' struct array
 * used by the gpu implementation of quicksort, as well as to calculate
 * the time of execution of the sorting algorithm.
 *
 * Parameters:
 * unsorted: The array of floats to be sorted
 * length: The length of the unsorted and sorted arrays
 * sorted: An output parameter, to be filled with the sorted array.
 *
 * Output:
 * time: This function returns the time of execution required by the
 *       sorting algorithm
 */
double gpu_quicksort(float unsorted[], int length, float sorted[]){
  time_t start, end;
  double time;    

  for(int i = 0; i < length; i++)
    sorted[i] = unsorted[i];

  start = clock();
  gqSort(sorted, 0, length - 1, length);
  end = clock();
  time = ((double) end - start) / CLOCKS_PER_SEC;

  return time;
}

/* quicksort
 * 
 * This function is called by main to populate a result, testing the CPU
 * and GPU implementations of quicksort.
 *
 * Parameters:
 * unsorted: an unsorted array of floating points
 * length: the length of the unsorted array
 * result: an output parameter to be filled with the results of the cpu and gpu
 *         implementations of quicksort.
 *
 */
void quicksort(float unsorted[], int length, Result * result){
  result = (Result *) malloc(sizeof(Result));

  cudaPrintfInit();
  
  if(result == NULL){
    fprintf(stderr, "Out of Memory\n");
    exit(1);
  }
  strcpy(result->tname, "Quick Sort");
  float sorted[2][length];

  result->cpu_time = cpu_quicksort(unsorted, length, sorted[0]);
  result->gpu_time = gpu_quicksort(unsorted, length, sorted[1]);

  //check that sorted[0] = sorted[1];
  int n = 0;
  for(int i = 0; i < length; i++){
    if(sorted[0][i] != sorted[1][i])
      n++;
    //    printf("CPU #%d: %f\t", i, sorted[0][i]); 
    //    printf("GPU #%d: %f", i, sorted[1][i]); 
    //    printf("\n", i, sorted[0][i]); 

  }

  cudaThreadSynchronize();
  cudaPrintfDisplay(stdout,true);
  cudaPrintfEnd();

  if(n != 0){
    fprintf(stdout, "There were %d discrepencies between the CPU and GPU QuickSort algorithms\n", n);
  }

  return;
}
