# Assembly and Compilation
as --32 boot.S -o boot.o
gcc -m32 -c drivers.S -o drivers.o
gcc -m32 -c kernel.S -o kernel.o
gcc -m32 -c commands.c -o commands.o -std=gnu99 -ffreestanding -O2 -fno-stack-protector

# Link (boot.o MUST come first)
ld -m elf_i386 -T linker.ld -o openos.elf boot.o drivers.o kernel.o commands.o

# Flatten and Run
objcopy -O binary openos.elf openos.bin