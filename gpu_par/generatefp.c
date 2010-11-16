#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <time.h>

#define LENGTH 100000000
#define EPSILON 0.000001
int main(int argc, char **argv){
  int length;
  if(argc == 2)
    length = *(argv[1]);
  else
    length = LENGTH;
  float f = 0.0;
  FILE * control, * disorder, * inverse;
  float * ar = malloc(sizeof(float)*length);
  if(ar == NULL)
    exit(1);
  float * back_ar = malloc(sizeof(float)*length);
  if(back_ar == NULL)
    exit(1);
  float * mixed_ar = malloc(sizeof(float)*length);
  if(mixed_ar == NULL)
    exit(1);

  control = fopen("array0.ls", "w");
  inverse = fopen("array7.ls", "w");
  fprintf(control,"#%d#", length);
  fprintf(inverse,"#%d#",length);

  fprintf(stdout, "Writing control and inverse lists.");
  for(long i = 0; i < length; i++){
    ar[i] = f;
    mixed_ar[i] = f;
    back_ar[length-1-i] = f;
    f += EPSILON;
    fprintf(control,"%f ",ar[i]);
    fprintf(inverse,"%f ",back_ar[i]);
    if((i % 1000000) == 0)
      fprintf(stdout,".");
  }
  fprintf(stdout,"\n");
  fprintf(control,"\n");
  fprintf(inverse,"\n");
  fclose(control);
  fclose(inverse);
  free(back_ar);

  for(int j = 1; j <= 6; ++j){
    switch(j){
    case 1:
      disorder = fopen("array1.ls", "w");
      break;
    case 2:
      disorder = fopen("array2.ls", "w");
      break;
    case 3:
      disorder = fopen("array3.ls", "w");
      break;
    case 4:
      disorder = fopen("array4.ls", "w");
      break;
    case 5:
      disorder = fopen("array5.ls", "w");
      break;
    default:
      disorder = fopen("array6.ls", "w");
      break;
    }
    fprintf(disorder, "#%d#", length);
    fprintf(stdout,"Randomly swapping list elements.");
    for(long i = 0; i < length; i++){
      srand(time(NULL));
      long k = rand() % (length + 1);
      float temp = mixed_ar[k];
      mixed_ar[k] = mixed_ar[i];
      mixed_ar[i] = temp;
      if((i % 1000000) == 0)
	fprintf(stdout,".");
    }
    fprintf(stdout,"\n");
    fprintf(stdout,"Writing unordered list %d.", j);
    for(long i = 0; i < length; i++){
      fprintf(disorder, "%f ", mixed_ar[i]);
      if((i % 1000000) == 0){
	fprintf(stdout,".");
      }
    }
    fprintf(stdout,"\n");
    fprintf(disorder, "\n");
    fclose(disorder);
  }
  free(ar);
  free(mixed_ar);
  return 0;
}
