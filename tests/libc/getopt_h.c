/* run.config
   STDOPT: #"-eva-precision 7 -eva-verbose 0"
*/

// Test case based on glibc's manual example with getopt_long:
// www.gnu.org/software/libc/manual/html_node/Getopt-Long-Option-Example.html

#include <stdio.h>
#include <getopt.h>
#include "__fc_builtin.h"

/* Flag set by ‘--verbose’. */
static int verbose_flag;

volatile int v;
int main () {
  int argc = Frama_C_interval(0, 4);
  char argv_data[4][32];
  for (int i = 0; i < 4; i++) {
    for (int j = 0; j < 31; j++) {
      argv_data[i][j] = v;
    }
    argv_data[i][31] = 0;
  }
  char *argv[5];
  argv[0] = argv_data[0];
  argv[1] = argv_data[1];
  argv[2] = argv_data[2];
  argv[3] = argv_data[3];
  argv[4] = 0;

  int c;

  while (1) {
    static struct option long_options[] =
      {
        /* These options set a flag. */
        {"verbose", no_argument,       &verbose_flag, 1},
        {"brief",   no_argument,       &verbose_flag, 0},
        /* These options don’t set a flag.
           We distinguish them by their indices. */
        {"add",     no_argument,       0, 'a'},
        {"append",  no_argument,       0, 'b'},
        {"create",  required_argument, 0, 'c'},
        {0, 0, 0, 0}
      };
    /* getopt_long stores the option index here. */
    int option_index;
    // test call with last argument null
    c = getopt_long (argc, argv, "abc:",
                     long_options, 0);
    // test call with last argument not null
    c = getopt_long (argc, argv, "abc:",
                     long_options, &option_index);
    /* Detect the end of the options. */
    if (c == -1) break;
    switch (c) {
    case 0:
      /* If this option set a flag, do nothing else now. */
      if (long_options[option_index].flag != 0) break;
      printf ("option %s", long_options[option_index].name);
      if (optarg) printf (" with arg %s", optarg);
      break;
    case 'a':
      puts ("option -a\n");
      break;
    case 'b':
      puts ("option -b\n");
      break;
    case 'c':
      printf ("option -c with value `%s'\n", optarg);
      break;
    case '?':
      /* getopt_long already printed an error message. */
      break;
    default:
      return 1;
    }
  }
  /* Instead of reporting ‘--verbose’
     and ‘--brief’ as they are encountered,
     we report the final status resulting from them. */
  if (verbose_flag)
    puts ("verbose flag is set");
  /* Print any remaining command line arguments (not options). */
  if (optind < argc) {
    printf ("non-option ARGV-elements: ");
    while (optind < argc)
      printf ("%s ", argv[optind++]);
    putchar ('\n');
  }
  return 0;
}
