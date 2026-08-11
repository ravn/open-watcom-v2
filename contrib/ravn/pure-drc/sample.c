/* Smallest pure Digital Research C smoke test (CP/M-86).
 *
 * Compiled by the genuine DR C v1.11 compiler and linked against the real DR C
 * run-time (clears.l86) with DR LINK-86.  Unlike the freestanding examples in
 * ../owc-drc, this uses DR C's own libc printf and its own startup (m.init),
 * so it exercises the full run-time entry chain -- see ../pure-drc/README.md.
 *
 * Expected output (identical in the cpm86/emu2 emulator and in
 * ../cpm86run_unicorn.py):
 *
 *   0 TESTING C
 *   1 TESTING C
 *   2 TESTING C
 *   3 TESTING C
 *
 *   FINISHED!
 */
main()
{
  int val;

  for (val = 0; val <= 3; val++)
    printf("%d TESTING C\n", val);

  printf("\n");
  printf("FINISHED!\n");
}
