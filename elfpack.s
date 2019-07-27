# simple elf packer.
# 
# by wzt 2018
#

.text
.global main

check_elf_header:
	push %rbp
	mov %rsp, %rbp

	sub $8, %rsp
	movq $-1, -0x8(%rbp)

	movzbl (%rdi), %eax
	cmp $0x7f, %al
	jnz 2f
	movzbl 1(%rdi), %eax
	cmp $0x45, %al
	jnz 2f
	movzbl 2(%rdi), %eax
	cmp $0x4c, %al
	jnz 2f
	movzbl 3(%rdi), %eax
	cmp $0x46, %al
	jnz 2f
	movq $0, -0x8(%rbp)
2:
	mov -0x8(%rbp), %rax
	mov %rbp, %rsp
	pop %rbp
	ret

elf_init:
	push %rbx
	push %rbp
	mov %rsp, %rbp
	sub $0xb0, %rsp

	movw $-1, -0x14(%rbp)		# rc

	mov %rdi, -0x8(%rbp)		# path
	mov $2, %esi
	mov $0x1ff, %edx
	mov $2, %rax
	syscall
	mov $m_fd, %rbx
	mov %eax, (%rbx)
	cmp $0, %rax
	js 1f
	
	mov $4, %rax
	mov -0x8(%rbp), %rdi
	lea -0xb0(%rbp), %rsi
	syscall
	cmp $0, %rax
	js 2f
	lea -0xb0(%rbp), %rax
	mov 0x30(%rax), %rax
	mov $m_size, %rbx
	mov %rax, (%rbx)

	mov $9, %rax
	mov $0, %rdi
	mov m_size, %rsi
	mov m_fd, %rdx
	mov %edx, %r8d
	mov $3, %rdx
	mov $2, %r10d
	mov $0, %r9d
	syscall
	cmp $0, %rax
	js 3f
	mov %rax, -0x10(%rbp)		# addr

	mov -0x10(%rbp), %rdi
	call check_elf_header
	mov %eax, -0x14(%rbp)		
	cmp $0, %rax
	js 3f

	mov $e_hdr, %rax
	mov -0x10(%rbp), %rbx
	movq %rbx, (%rax)
	jmp 1f
3:
	mov -0x10(%rbp), %rdi
	mov m_size, %rsi
	mov $11, %rax
	syscall
2:
	mov m_fd, %rdi
	mov $3, %rax
	syscall
1:
	mov -0x14(%rbp), %eax
	mov %rbp, %rsp
	pop %rbp
	pop %rbx
	ret

elf_fini:
	push %rbp
	mov %rsp, %rbp

	mov e_hdr, %rdi
	mov m_size, %rsi
	mov $11, %rax
	syscall

	mov $3, %rax
	mov m_fd, %rdi
	syscall

	xor %rax, %rax
	mov %rbp, %rsp
	pop %rbp
	ret

# the _start function will use rdx, rsi, rax, rsp, 
# save them first on the stack.
pack_text_start:
pack_text:
	call 4f
3:
	pop %r15
	push %rdx
	push %rsi
        push %rbx
        push %r12
        push %r13
        push %r14
        push %r15
        push %rbp
        mov %rsp, %rbp

	# the frame of the orig _start entry as follows:
	# rsp->argc
	# rsp+0x8->argv
	# rsp+0x18->env
	#
	# push rdx->rbp is 64 bytes.
	mov 0x48(%rsp), %r13
	sub $0xb0, %rsp

        # already been debugged?
/*
        mov $0, %rdi
        mov $0, %rsi
        mov $0, %rdx
        mov $0, %r10
        mov $101, %rax
        syscall
        cmp $0, %rax
        jnz 10f
*/
	movq 0x48(%rbp), %rdi
	mov $0, %esi
	mov $0x1ff, %edx
	mov $2, %rax
	syscall
	movl %eax, -0x4(%rbp)	# fd
	cmp $0, %eax
	js 11f

	movq 0x48(%rbp), %rdi
	lea -0xb0(%rbp), %rsi
	mov $4, %rax
	syscall
	cmp $0, %eax
	js 11f
	
	mov $0, %rdi
	movq 0x30(%rsi), %rsi	
	movl %esi, -0x8(%rbp)	# st_size
	mov $1, %rdx
	mov $2, %r10
	movl -0x4(%rbp), %r8d
	mov $0, %r9
	mov $9, %rax
	syscall
	cmpq $0, %rax
	js 11f
	movq %rax, -0x10(%rbp)	# addr

	# decrypt text first.
	sub $5, %r14
	# escape call+pop %r14 length
	sub $7, %r15
	movq -0x10(%r14), %r12
	movq -0x8(%r14), %r13
1:
        cmp $0, %r13
        jle 2f
        movb (%r12), %bl
        xorb $1, %bl
        movb %bl, (%r12)
        add $1, %r12
        sub $1, %r13
        jmp 1b
2:
	# copy _start code.
	movq -0x10(%r14), %r12
	xor %r13, %r13
18:
	movb (%r12), %bl
	movb %bl, (%r15)
	cmpb $0xf4, (%r12)	# halt
	jnz 19f
	cmpb $0xe8, -0x5(%r12)	# call _libc_start_main
	jnz 19f
	movl -0x4(%r12), %ecx
	add %ecx, %r12d		# _libc_start_main address.
	sub %r15d, %r12d
	movl %r12d, -0x4(%r15)	# fill new offset.
	jmp 20f
19:
	add $1, %r15
	add $1, %r12
	add $1, %r13
	jmp 18b

	# erase _start code.
20:
	movq -0x10(%r14), %r12
21:
	cmp $0, %r13
	jl 22f
	movb $0x90, (%r12)
	add $1, %r12
	sub $1, %r13
	jmp 21b
22:
	# modify got table.
	mov -0x10(%rbp), %rcx	# e_hdr
	movq 0x28(%rcx), %rdi	# shoff
	addq %rcx, %rdi
	movw 0x3c(%rcx), %si	# shnum
	movw 0x3a(%rcx), %dx	# shentsize
12:
	cmpw $0, %si
	jle 13f
	cmpl $4, 0x4(%rdi)	# rela
	jz 14f
	cmpl $9, 0x4(%rdi)	# rel
	jnz 15f
14:
	# handle rela.
	movq 0x18(%rdi), %r12	# rela addr
	addq %rcx, %r12
	movq 0x20(%rdi), %r15	# rela size
	movq 0x38(%rdi), %r13	# rela ent size

	movq -0x20(%r14), %rax
	addq -0x18(%r14), %rax
	sub $8, %rax
	movq %rax, -0x28(%rbp)	# current new got address.

	movq $0, -0x20(%rbp)	# i
16:
	cmp -0x20(%rbp), %r15
	jle 15f
	movq 0x8(%r12), %rax
	movq $0xffffffff, %rbx
	andq %rbx, %rax
	cmp $7, %rax
	jnz 17f
	movq -0x28(%rbp), %rbx
	movq $0x9090909090909090, %rax
	cmp %rax, (%rbx)
	jnz 15f

	# fill new got entry
	movb $0xff, (%rbx)
	movb $0x25, 1(%rbx)
	mov (%r12), %rax	# r_offset
	sub -0x28(%rbp), %rax
	sub $6, %rax
	movl %eax, 2(%rbx)

	# hijack orig plt entry
	mov (%r12), %rax
	mov (%rax), %rax
	sub $6, %rax
	movb $0xe9, (%rax)
	add $5, %rax
	sub %rax, %rbx
	movl %ebx, -0x4(%rax)

	sub $8, -0x28(%rbp)
17:
	add %r13, -0x20(%rbp)
	add %r13, %r12
	jmp 16b
15:
	sub $1, %si
	addq %rdx, %rdi
	jmp 12b
13:

	# earse self code in the memory.
	call 5f
5:
	pop %r12
	mov %r14, %r13
	movb $0x90, %bl
	sub %r14, %r12
6:
	cmp $0, %r12
	jz 7f
	movb %bl, (%r13)
	sub $1, %r12
	add $1, %r13
	jmp 6b
7:
	# earse elf header.
	movq -0x20(%r14), %rdi
	movb $0, %bl
	mov $0x40, %rsi
8:
	cmp $0, %rsi
	jl 9f
	movb %bl, (%rdi)
	sub $1, %rsi
	add $1, %rdi
	jmp 8b
9:
	# modify pt_load text flag as r+x.
	movq -0x20(%r14), %rdi
	movq -0x18(%r14), %rsi
	mov $5, %rdx
	mov $10, %rax
	syscall
	
/*
	# modify elf header as non read access.
	movq -0x20(%r14), %rdi
	movq $0x40, %rsi
	mov $1, %rdx
	mov $10, %rax
	syscall
*/
	jmp 11f
10:
        mov $0, %rdi
        mov $60, %rax
        syscall
11:
	movl -0x4(%rbp), %edi
	mov $3, %rax
	syscall

	movq -0x10(%rbp), %rdi
	movl -0x8(%rbp), %esi
	mov $11, %rax
	syscall

        mov %rbp, %rsp
        pop %rbp
        pop %r15
        pop %r14
        pop %r13
        pop %r12
        pop %rbx
	pop %rsi
	pop %rdx

	# copy _start code from here, code below will be replaced.
4:
	pop %r14
	call 3b
pack_text_end:

# rdi - source address, rsi - length
encrypt_text:
        push %rbx
        push %r12
        push %r13
        push %r14
        push %r15
        push %rbp
        mov %rsp, %rbp

	mov %rdi, %r12
	mov %rsi, %r13
1:
	cmp $0, %r13
	jle 2f
	movb (%r12), %bl
	xorb $1, %bl
	movb %bl, (%r12)
	add $1, %r12
	sub $1, %r13
	jmp 1b
2:
        xor %rax, %rax
        mov %rbp, %rsp
        pop %rbp
        pop %r15
        pop %r14
        pop %r13
        pop %r12
        pop %rbx
        ret

expand_program_header:
	push %rbx
	push %r12
	push %r13
	push %r14
	push %r15
	push %rbp
	mov %rsp, %rbp
	sub $0x20, %rsp
	movq $0, -0x8(%rbp)
	movl $0, -0xc(%rbp)	# flag
	movl $-1, -0x20(%rbp)	# rc

	mov e_hdr, %r12
	cmp $0, %r12
	jz 2f

        # save orig entry point.
        mov 0x18(%r12), %rax
        mov $orig_entry, %rdi
        mov %rax, (%rdi)

        movw 0x38(%r12), %ax
        movw %ax, -0x8(%rbp)	# phnum
	
        mov $e_phdr, %rax
        mov 0x20(%r12), %rbx	# phoff
        add %r12, %rbx
        mov %rbx, (%rax)
	mov %rbx, %r13
	mov %r13, %r15
	movl -0x8(%rbp), %r12d
1:
	cmp -0x4(%rbp), %r12d
	jle 2f

	# find first PT_LOAD.
	movl (%r13), %ebx
	cmpl $1, %ebx
	jnz 3f

	# is packed already?
        movq 0x8(%r13), %rax
        add 0x20(%r13), %rax
	add e_hdr, %rax
	movq $0x9090909090909090, %rbx
	cmp %rbx, -8(%rax)
	jnz 7f
	mov $pack_warn, %rdi
	mov $0, %rax
	call printf
	jmp 2f
7:
	# check pt_load size.
        movq 0x20(%r13), %rax
	add $0x1000, %rax
	cmp $0x200000, %rax
	jae 2f

	# save pt_text p_vaddr.
	mov $pt_text, %rax
	movq 0x10(%r13), %rbx
	movq %rbx, (%rax)

        # set new entry point.
	mov e_hdr, %rbx
        movq 0x10(%r13), %rax
        add 0x20(%r13), %rax

	# !!escape pt_text|pt_text_length|text|text_length
        add $0x20, %rax
        mov %rax, 0x18(%rbx)

	# offset + size
	movq 0x8(%r13), %r14
	addq 0x28(%r13), %r14
	mov %r14, %rcx
	addq e_hdr, %rcx
	mov $text_end, %rax
	mov %rcx, (%rax)
	movl $1, -0xc(%rbp)

	# modify filesz
	movq 0x20(%r13), %rbx
	addq $0x1000, %rbx
	movq %rbx, 0x20(%r13)

	# modify filesz
	movq 0x28(%r13), %rbx
	addq $0x1000, %rbx
	movq %rbx, 0x28(%r13)

	# save pt_text length.
	mov $pt_text_length, %rax
	movq %rbx, (%rax)

	# modify flag as rwx
	movl $7, %ebx
	movl %ebx, 0x4(%r13)

	movq $a_1, %rdi
	mov $0, %eax
	call printf
	jmp 4f
3:
	add $1, -0x4(%rbp)
	add $0x38, %r13
	jmp 1b

	# not found PT_LOAD
	cmpl $1, -0xc(%rbp)
	jnz 2f
4:
	movl $0, -0x4(%rbp)
	movl -0x8(%rbp), %r12d
5:
	cmp -0x4(%rbp), %r12d
	jle 2f
	cmp 0x8(%r15), %r14
	jae 6f
	
	# modify offset
	movq 0x8(%r15), %rbx
	addq $0x1000, %rbx
	movq %rbx, 0x8(%r15)

	movq $a_2, %rdi
	movq 0x8(%r15), %rsi
	mov $0, %eax
	call printf
	movl $0, -0x20(%rbp)
6:
	add $1, -0x4(%rbp)
	add $0x38, %r15
	jmp 5b
2:
	movl -0x20(%rbp), %eax
	mov %rbp, %rsp
	pop %rbp
	pop %r15
	pop %r14
	pop %r13
	pop %r12
	pop %rbx
	ret

expand_text_section:
	push %rbx
	push %r12
	push %r13
	push %r14
	push %r15
	push %rbp
	mov %rsp, %rbp
	sub $0xe0, %rsp

	mov e_hdr, %r12
	cmp $0, %r12
	jz 2f

	movw 0x3c(%r12), %ax
	movw %ax, -0x4(%rbp)	# shnum
	
	movw 0x3e(%r12), %ax	# shstrtab
	movw %ax, -0xc(%rbp)

	mov $e_shdr, %rbx
	movq 0x28(%r12), %rax	# shoff
	add %r12, %rax
	mov %rax, (%rbx)
	mov %rax, %r12

	movzwl -0xc(%rbp), %eax
	movw $0x40, %bx
	mul %bx
	mov %rax, %r14
	add %r12, %r14
	mov 0x18(%r14), %r14
	add e_hdr, %r14		# shstrtab_mem

	movl $0, -0x8(%rbp)	# i
	movl -0x8(%rbp), %r13d
	movl $0, -0x10(%rbp)	# flag
1:
	cmpl %r13d, -0x4(%rbp)
	jle 9f

	# encrypt .text section
	movl (%r12), %r15d
	add %r14, %r15
	movq %r15, %rdi
	mov $text_str, %rsi
	call strcmp
	cmp $0, %rax
	jnz 10f
	
	mov $encrypt_str, %rdi
	mov $0, %rax
	call printf

	# save text address and size.
	mov orig_entry, %rdi
	mov $text_start, %rax
	movq %rdi, (%rax)

	mov 0x10(%r12), %rdi
	mov 0x20(%r12), %rax
	mov orig_entry, %rsi
	sub %rdi, %rsi
	sub %rsi, %rax
	mov $text_length, %rsi
	movq %rax, (%rsi)

	mov 0x18(%r12), %rdi
	mov 0x20(%r12), %rax
	sub text_length, %rax
	add e_hdr, %rdi
	add %rax, %rdi
	mov text_length, %rsi
	call encrypt_text
	jmp 3f
10:
	cmp $1, -0x10(%rbp)
	jz 4f

        movq 0x18(%r12), %rbx
        addq 0x20(%r12), %rbx
        add e_hdr, %rbx
	movq text_end, %rcx
	cmp %rcx, %rbx
	jnz 3f
	movq %rbx, -0x38(%rbp)	# text end memory address.
	mov $found_str, %rdi
	mov $0, %eax
	call printf

	# modify .text size
	movq 0x20(%r12), %rbx
	add $0x1000, %rbx
	mov %rbx, 0x20(%r12)
	movl $1, -0x10(%rbp)
	jmp 3f
4:
	# modify section after the .text
	mov $b_1, %rdi
	movq %r15, %rsi
	movq 0x18(%r12), %rdx
	mov $0, %eax
	call printf

	# modify offset
	movq 0x18(%r12), %rbx
	add $0x1000, %rbx
	mov %rbx, 0x18(%r12)
3:
	add $1, %r13d
	add $0x40, %r12
	jmp 1b
9:
	# modify elf header.
	mov e_hdr, %r12
        movq 0x28(%r12), %rax
	add $0x1000, %rax
	movq %rax, 0x28(%r12)

	movq -0x38(%rbp), %rbx

        # create new file.
	# snprintf(file_path, 0x80, "%s.pack", a);
	lea -0xe0(%rbp), %rdi
	mov $0x80, %rsi
	mov $file_fmt, %rdx
	mov file_ptr, %rcx
	mov $0, %rax
	call snprintf

	lea -0xe0(%rbp), %rdi
        mov $0x42, %esi
        mov $0x1ff, %edx
        mov $2, %rax
        syscall
        movl %eax, -0x28(%rbp)  # new_fd
        cmp $0, %rax
        js 2f

        # write first part to new file.
        movl -0x28(%rbp), %edi
        movq e_hdr, %rsi
        movq %rbx, %rdx
        sub %rsi, %rdx
        mov $1, %rax
        syscall
        cmp $0, %rax
        js 5f

        # write second part to new file.
	# !! write pt_text|pt_text_length|text|text_length.
        movl -0x28(%rbp), %edi
	movq pt_text, %rax
	mov %rax, -0x60(%rbp)
	movq pt_text_length, %rax
	mov %rax, -0x58(%rbp)
	movq text_start, %rax
	mov %rax, -0x50(%rbp)
	movq text_length, %rax
	mov %rax, -0x48(%rbp)
	lea -0x60(%rbp), %rsi
	mov $0x20,%rdx
        mov $1, %rax
        syscall
        cmp $0, %rax
        js 5f

        movl -0x28(%rbp), %edi
        mov $pack_text_start, %rsi
        mov $pack_text_end, %rdx
        sub $pack_text_start, %rdx
        mov $1, %rax
        syscall
        cmp $0, %rax
        js 5f

	# fill nop with the rest memory.
        mov $0x1000, %rcx
        sub %rdx, %rcx
	# !!escape pt_text|pt_text_length|text|text_length
	sub $0x20, %rcx
        movb $0x90, -0x30(%rbp)
7:
        cmp $0, %rcx
        jle 8f
        push %rcx
        movl -0x28(%rbp), %edi
        lea -0x30(%rbp), %rsi
        mov $1, %rdx
        mov $1, %rax
        syscall
        pop %rcx
        cmp $0, %rax
        js 5f
        sub $1, %rcx
        jmp 7b
8:
        # write third part to new file.
	movq -0x38(%rbp), %rsi
	movq e_hdr, %rdi
	sub %rdi, %rsi
        movl m_size, %edx
        subl %esi, %edx
	movq -0x38(%rbp), %rsi
        movl -0x28(%rbp), %edi
        mov $1, %rax
        syscall
5:
        # close new file.
        movl -0x28(%rbp), %edi
        mov $3, %rax
        syscall
2:
	xor %rax, %rax
	mov %rbp, %rsp
	pop %rbp
	pop %r15
	pop %r14
	pop %r13
	pop %r12
	pop %rbx
	ret

elf_usage:
	push %rbp
	mov %rsp, %rbp
	mov %rdi, %rsi
	mov $usage_str, %rdi
	mov $0, %eax
	call printf
	mov %rbp, %rsp
	pop %rbp
	ret

main:
	push %rbp
	mov %rsp, %rbp
	sub $0x10, %rsp
	mov %rdi, -0x8(%rbp)
	mov %rsi, -0x10(%rbp)
	cmp $1, %rdi
	jnz 1f
	mov (%rsi), %rdi
	call elf_usage
	mov $0, %rax
	call exit
1:
	mov 0x8(%rsi), %rdi
	mov $file_ptr, %rax
	mov %rdi, (%rax)
	call elf_init
	cmp $0, %rax
	js 2f
	call expand_program_header
	cmp $0, %eax
	js 3f
	call expand_text_section
3:
	call elf_fini
2:
	mov %rbp, %rsp
	pop %rbp
	ret

.data
file_ptr:
	.quad 0
m_fd:
	.int 0
m_size:
	.long 0
e_hdr:
	.quad 0
e_phdr:
	.quad 0
e_phnum:
	.int 0
e_shdr:
	.quad 0
e_shnum:
	.int 0
text_start:
	.quad 0
text_end:
	.quad 0
text_length:
	.quad 0
pt_text:
	.quad 0
pt_text_length:
	.quad 0
orig_entry:
	.quad 0

usage_str:
	.asciz "usage: %s <bin>\n"
file_fmt:
	.asciz "%s.pack"
text_str:
	.string ".text"
found_str:
	.string "found .text section.\n"
encrypt_str:
	.string "encrypt .text section.\n"
pack_warn:
	.string "entry point is already modified.\n"
a_1:
	.string "found PT_LOAD.\n"
a_2:
	.string "modify program header 0x%x.\n"
b_1:
	.string "modify section %s offset 0x%x.\n"
