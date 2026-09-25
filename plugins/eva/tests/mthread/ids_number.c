/* run.config*
   EXIT: 1
   STDOPT: +"-eva-msg-key=-mutex"
   EXIT: 0
   STDOPT: +"-cpp-extra-args='-DMTHREAD_NUMBER_IDS=33' -eva-msg-key=-mutex"
*/

/* Tests changing the number of threads, mutexes and message queues that can be
   represented by the cvalue domain.
   This example uses 33 mutexes, so:
   - first run should abort with a clear error message (limit is 32 by default);
   - first run should succeed (limit is set to 33). */

#include <stddef.h>
#include <pthread.h>

int shared = 0;
volatile unsigned int nondet;

pthread_t       jobs1;
pthread_t       jobs2;

/* Requires MAX ids to represent each mutex in the Cvalue domain. */
#define MAX 33
pthread_mutex_t  mutex[MAX];

void *f(void *_) {
  //@ loop unroll MAX;
  for (int i = 0; i < MAX; i++)
    pthread_mutex_lock(&mutex[i]);
  /* This assignment is really well protected! */
  shared = shared + 1;
  //@ loop unroll MAX;
  for (int i = 0; i < MAX; i++)
    pthread_mutex_unlock(&mutex[i]);
  return NULL;
}

int main(void) {
  //@ loop unroll MAX;
  for (int i = 0; i < MAX; i++)
    pthread_mutex_init(&mutex[i], NULL);

  pthread_create(&jobs1, NULL, f, NULL);
  pthread_create(&jobs2, NULL, f, NULL);

  return 0;
}
