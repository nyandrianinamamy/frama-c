from dataclasses import dataclass
import random
import subprocess
import argparse
import os
import functools
from multiprocessing import Pool, freeze_support

parser = argparse.ArgumentParser()


@dataclass
class ParseArgs(argparse.Namespace):
    nb_tests: int
    nb_procs: int
    verbose: bool


_ = parser.add_argument("-n", "--nb-tests", type=int, default=100)
_ = parser.add_argument("-j", "--nb-procs", type=int, default=4)
_ = parser.add_argument("-v", "--verbose", action="store_true", default=False)

types = [
    ("_Bool", 1),
    ("unsigned char", 8),
    ("unsigned short", 16),
    ("unsigned int", 32),
    ("unsigned long", 64),
    ("unsigned long long", 64),
]

type struct = list[tuple[str, int | None]]


def flip():
    return random.choice([True, False])


def gen_layout() -> struct:
    res: list[tuple[str, int | None]] = []
    if flip():
        res.append((random.choice(types)[0], None))
    nb_fields = random.randint(1, 10)
    while nb_fields > 0:
        t, size = random.choice(types)
        bf_size = random.randint(0, size)
        res.append((t, bf_size))
        nb_fields -= 1
    if flip():
        res.append((random.choice(types)[0], None))
    nb_fields = random.randint(1, 10)
    while nb_fields > 0:
        t, size = random.choice(types)
        bf_size = random.randint(0, size)
        res.append((t, bf_size))
        nb_fields -= 1
    if flip():
        res.append((random.choice(types)[0], None))
    return res


def print_struct(filename: str, struct: struct) -> None:
    with open(filename, "w") as f:
        print("#include <stdio.h>", file=f)
        print("#include <string.h>", file=f)
        print(
            """
        size_t offset_bit(char* x, size_t s) {
        //@ loop unroll s;
        for(size_t i = 0; i < s; i++) {
        //@ loop unroll 8;
        for(unsigned j = 0; j < 8; j++) {
        if( *(x+i) >> j & 1) return i * 8 + j;
        }
        }
        return s;
        }
 
        void print(char* x, size_t s) {
        for (size_t i = 0; i < s; i++) {
        for (unsigned j = 0; j < 8; j++) {
        if (*(x+i) >> j & 1) printf(\"1\"); else printf("0");
        }
        printf(" ");
        }
        printf("\\n");
        }
        """,
            file=f,
        )
        print("typedef struct {", file=f)
        i = 0
        for t, s in struct:
            field = f"{t}"
            if s is None:
                field += f" f{i}"
            elif s == 0:
                field += " : 0"
            else:
                field += f" f{i}: {s}"
            field += ";"
            print(field, file=f)
            i += 1
        print("}", file=f)
        if flip():
            print("__attribute__((packed))", file=f)
        print("S;", file=f)
        print("S x;", file=f)
        print("int main() {", file=f)
        print("size_t o;", file=f)
        i = 0
        for t, s in struct:
            if s is not None and s != 0:
                print("memset(&x,0,sizeof(x));", file=f)
                print(f"x.f{i} = (1ULL << {s}) - 1;", file=f)
                print("o = offset_bit((char*)&x, sizeof(x));", file=f)
                print(f'printf("f{i} at offset %zu\\n",o);', file=f)
                print("print((char*)&x,sizeof(x));", file=f)
            i += 1
        print("}", file=f)


def check(verbose: bool, test_id: int):
    struct = gen_layout()
    filename = f"file_{test_id}.c"
    print_struct(filename, struct)
    if verbose:
        print(f"Generating struct in {filename}")
    res = subprocess.run(
        ["frama-c", "-typecheck", "-check", filename], text=True, capture_output=True
    )
    if res.returncode != 0:
        print(f"bitfield definition in {filename} led to ill-formed AST. Frama-C output is:")
        print(res.stdout)
        return False
    if not verbose:
        os.remove(filename)
    return True


def main():
    args = parser.parse_args(namespace=ParseArgs)
    tests = range(args.nb_tests)
    res = []
    if args.nb_procs > 1:
        if __name__ == "__main__":
            with Pool(args.nb_procs) as p:
                res = p.map(functools.partial(check, args.verbose), tests)
    else:
        res = map(lambda x: check(args.verbose, x), tests)
    for b in res:
        if not b:
            exit(1)


main()
