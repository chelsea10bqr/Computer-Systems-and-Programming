
.data					# section declaration

        # Useful offset constants for accessing members of a
        # struct mp1_blink_struct structure
        LOCATION   = 0
        ON_CHAR    = 2
        OFF_CHAR   = 3
        ON_LENGTH  = 4
        OFF_LENGTH = 6
        COUNTDOWN  = 8
        STATUS     = 10
        NEXT       = 12

        STRUCT_SIZE = 16
        RANGE_CHECK = 1999 # the bound of the text-mode video range
# Pointer to head of list (initialized to NULL)
mp1_list_head:
        .long   0

.text					# section declaration

# Export the function symbol names

.global mp1_rtc_tasklet
.global mp1_ioctl

# void mp1_poke(void);
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX
mp1_poke:

    movl    vmem_base_addr(,1),%edx
    movb    %cl,(%edx,%eax,1)
    ret

# void mp1_rtc_tasklet(unsigned long);
#
# Interface: Register-based arguments (not C-style)
#    Inputs:  unsigned long
#   Outputs: update the game status
# Registers: %ebx(head pointer)

mp1_rtc_tasklet:
    # ebx(head pointer),
    pushl %ebp
    movl %esp,%ebp
    pushl %ebx
    pushl %esi
    pushl %edi
    pushl %ecx
    # get the head pointer
    movl mp1_list_head,%ebx
loop_start:
    # decrease the countdown
    xorl %esi,%esi
    movw COUNTDOWN(%ebx),%si
    addw $-1,%si
    movw %si,COUNTDOWN(%ebx)
    # check whether it is 0
    cmpw $0,%si
    je check_status
    movl NEXT(%ebx),%ebx
    cmpl $0,%ebx
    jz loop_done
    jmp loop_start
check_status:
    xorl %edi,%edi
    movw STATUS(%ebx),%di
    # it is 1, should turn off
    cmpw $1,%di
    je turn_off
    # call mp1_poke on char(turn_on)
    xorl %ecx,%ecx
    movw LOCATION(%ebx),%cx
    addl %ecx,%ecx
    movl %ecx,%eax
    movb ON_CHAR(%ebx),%cl
    call mp1_poke
    xorl %ecx,%ecx
    # change the value to on_length
    movw ON_LENGTH(%ebx),%cx
    movw %cx,COUNTDOWN(%ebx)
    movw $1,STATUS(%ebx)
    xorl %ecx,%ecx
    movl NEXT(%ebx),%ecx
    cmpl $0,%ecx
    jz loop_done
    movl NEXT(%ebx),%ebx
    jmp loop_start
turn_off:
    xorl %ecx,%ecx
    movw LOCATION(%ebx),%cx
    addl %ecx,%ecx
    movl %ecx,%eax
    movb OFF_CHAR(%ebx),%cl
    call mp1_poke
    xorl %ecx,%ecx
    # change the value to off_length
    movw OFF_LENGTH(%ebx),%cx
    movw %cx,COUNTDOWN(%ebx)
    movw $0,STATUS(%ebx)
    movl NEXT(%ebx),%ebx
    cmpl $0,%ebx
    jz loop_done
    jmp loop_start
loop_done:
    popl %ecx
    popl %edi
    popl %esi
    popl %ebx
    leave
    ret

mp1_ioctl:
    # get the parameter
    movl 8(%esp),%ebx
    cmpl $3,%ebx
    # greater than 3 is not valid
    ja invalid
    cmpl $0,%ebx
    # less than 0 is not valid
    jl invalid
    # jumptable
    jmp *jumptable(,%ebx,4)

invalid:
    # not valid, return -1
    movl $-1,%eax
    ret



jumptable:
    .long	mp1_ioctl_add, mp1_ioctl_remove,mp1_ioctl_find, mp1_ioctl_sync

# int mp1_ioctl_add(unsigned long arg);
#
# Interface: Register-based arguments (not C-style)
#    Inputs: the user_level pointer of an element
#   Outputs: add one element at the head of the list,sucess return 0, fail return -1
# Registers: esi(user_level pointer) ebx(alllocated pointer)
mp1_ioctl_add:
    # store ebp value
    # store and update ebp, push ebx, esi
    pushl %ebp
    movl %esp,%ebp
    # get the arguments
    pushl %ebx
    pushl %esi
    pushl %edi
    pushl %ecx
    pushl %edx
    movl 8(%ebp),%ebx
    # allocate a structure
    pushl $STRUCT_SIZE
    call mp1_malloc
    addl $4,%esp
    movl %eax,%esi
    # whether it failures
    cmpl $0,%ebx
    je failure
    # store the pointer to edi
    pushl $STRUCT_SIZE
    pushl %ebx
    pushl %esi
    # copy from user space
    call mp1_copy_from_user
    addl $12,%esp
    # check whether all bytes copied
    cmpl $0,%eax
    jne copy_failure
    # get the location value, check wheter in range
    xorl %ecx,%ecx
    movw LOCATION(%esi),%cx
    cmpw $0,%cx
    jl copy_failure
    cmpw $RANGE_CHECK,%cx
    ja copy_failure
    # change the value of parameter
    xorl %edx,%edx
    movw ON_LENGTH(%esi),%dx
    movw %dx,COUNTDOWN(%esi)
    movw $1,STATUS(%esi)
    # add to the beginning of the list
    movl mp1_list_head,%edx
    movl %edx,NEXT(%esi)
    movl %esi,mp1_list_head
    # call mp1_poke to draw
    # move the char of on into cl register
    xorl %edx,%edx
    movw LOCATION(%esi),%dx
    addl %edx,%edx
    movl %edx,%eax
    movb ON_CHAR(%esi),%cl
    call mp1_poke
    # success return 0
    movl $0,%eax
    # restore value
    popl %edx
    popl %ecx
    popl %edi
    popl %esi
    popl %ebx
    leave
    ret
copy_failure:
    # free space
    pushl %ebx
    call mp1_free
    addl $4,%esp
failure:
    # return -1
    movl $-1,%eax
    popl %edx
    popl %ecx
    popl %edi
    popl %esi
    popl %ebx
    leave
    ret

# int mp1_ioctl_remove(unsigned long arg);
#
# Interface: Register-based arguments (not C-style)
#    Inputs: the integer of the location
#   Outputs: remove one of the element from list, if sucess return 0, fail return -1
# Registers: ebx(location arguments) eax(the return value from mp1_search)
mp1_ioctl_remove:
    pushl %ebp
    movl %esp,%ebp
    pushl %ebx
    pushl %ecx
    pushl %esi
    pushl %edi
    # get the parameter
    xorl %ebx,%ebx
    movl 8(%ebp),%ebx
    pushl %ebx
    call mp1_search
    addl $4,%esp
    cmpl $-1,%eax
    je cant_find
    # check whether it is head of the list
    cmpl %eax,mp1_list_head
    je is_head
    # remove the element
    movl NEXT(%eax),%esi
    movl %esi,NEXT(%ecx)
    jmp free_memory
is_head:
    movl NEXT(%eax),%edi
    movl %edi,mp1_list_head
free_memory:
    # free the memory
    pushl %eax
    call mp1_free
    addl $4,%esp
    movl $0,%eax
    popl %edi
    popl %esi
    popl %ecx
    popl %ebx
    leave
    ret
cant_find:
    # cant find  return -1
    movl $-1,%eax
    popl %edi
    popl %esi
    popl %ecx
    popl %ebx
    leave
    ret

# int mp1_ioctl_find(unsigned long arg);
#
# Interface: Register-based arguments (not C-style)
#    Inputs: the pointer of a structure
#   Outputs: find the element with the same location, and copy to user_level, if sucess return 0, fail return -1
# Registers: ebx(pointer of structure) eax(the return value from mp1_search) edx(location value)
mp1_ioctl_find:
    pushl %ebp
    movl %esp,%ebp
    pushl %ebx
    pushl %edx
    pushl %ecx

    movl 8(%ebp),%ebx
    # check whether the structure valid
    cmpl $0,%ebx
    je outside
    xorl %edx,%edx
    # check whether in range
    movw LOCATION(%ebx),%dx
    cmpw $0,%dx
    jl outside
    cmpw $RANGE_CHECK,%dx
    ja outside
    pushl %edx
    # call helpler function to find the element
    call mp1_search
    addl $4,%esp
    # check whether find it
    cmpl $-1,%eax
    je outside
    pushl $STRUCT_SIZE
    pushl %eax
    pushl %ebx
    call mp1_copy_to_user  # copy to user
    addl $12,%esp
    cmpl $0,%eax
    # check whether copy success
    jne outside
    popl %ecx
    popl %edx
    popl %ebx
    leave
    ret
outside:
    movl $-1,%eax
    popl %ecx
    popl %edx
    popl %ebx
    leave
    ret

# int mp1_ioctl_sync(unsigned long arg);
#
# Interface: Register-based arguments (not C-style)
#    Inputs: an int contained two location parameter, upper-16 is first, lower-16 is second
#   Outputs: copy the first timing field into second, if sucess return 0, fail return -1
# Registers: ebx(the first element location) edx(the second element location)
#             edi(the first element pointer) esi(the second element pointer)
mp1_ioctl_sync:
    pushl %ebp
    movl %esp,%ebp
    pushl %ebx
    pushl %ecx
    pushl %edx
    pushl %edi
    pushl %esi
    xorl %ebx,%ebx
    xorl %ecx,%ecx
    movw 8(%ebp),%bx
    movw 10(%ebp),%cx
    # check whether two location value valid
    cmpw $0,%bx
    jl not_range
    cmpw $RANGE_CHECK,%bx
    ja not_range
    cmpw $0,%cx
    jl not_range
    cmpw $RANGE_CHECK,%cx
    ja not_range
    # search the address of these two elements  esi (second)   edi (first)
    xorl %esi,%esi
    xorl %edi,%edi
    pushl %ecx
    pushl %ebx
    call mp1_search
    addl $4,%esp
    popl %ecx
    movl %eax,%esi
    cmpl $-1,%esi
    je not_range
    pushl %ecx
    pushl %ecx
    call mp1_search
    addl $4,%esp
    popl %ecx
    movl %eax,%edi
    cmpl $-1,%edi
    je not_range
    # copy the first into second
    xorl %edx,%edx
    movw ON_LENGTH(%edi),%dx
    movw %dx,ON_LENGTH(%esi)
    movw OFF_LENGTH(%edi),%dx
    movw %dx,OFF_LENGTH(%esi)
    movw COUNTDOWN(%edi),%dx
    movw %dx,COUNTDOWN(%esi)
    movw STATUS(%edi),%dx
    movw %dx,STATUS(%esi)
    # call mp1_poke for second element, check the status
    cmpw $1,%dx
    je ON_C
    movb OFF_CHAR(%esi),%cl
    xorl %edx,%edx
    movw LOCATION(%esi),%dx
    addl %edx,%edx
    movl %edx,%eax
    call mp1_poke
    jmp done
ON_C:
    # this is for ON_CHAR copy
    movb ON_CHAR(%esi),%cl
    xorl %edx,%edx
    movw LOCATION(%esi),%dx
    addl %edx,%edx
    movl %edx,%eax
    call mp1_poke
done:
    movl $0,%eax
    popl %esi
    popl %edi
    popl %edx
    popl %ecx
    popl %ebx
    leave
    ret
not_range:
    movl $-1,%eax
    popl %esi
    popl %edi
    popl %edx
    popl %ecx
    popl %ebx
    leave
    ret

# int mp1_search(unsigned long arg);
#
# Interface: Register-based arguments (not C-style)
#    Inputs: the location which we need to search in a linked-list
#   Outputs: returen the address of this element,fail return -1
# Registers: ebx(location arg) edx(the list pointer)
#             ecx(caller-saved, the last element in linked list)
mp1_search:
    # linked list search   arguments(LOCATION)  success return address of this element
    # fails return -1,     %ebx(location arg) %esi(list pointer)  %ecx(the last element in linked list)
    pushl %ebp
    movl %esp,%ebp
    pushl %ebx
    pushl %edx
    pushl %esi
    pushl %edi
    # get the parameter
    xorl %ebx,%ebx
    movl 8(%ebp),%ebx
    # check whether in range
    cmpw $0,%bx
    jl not_valid
    cmpw $RANGE_CHECK,%bx
    ja not_valid
    xorl %esi,%esi
    xorl %ecx,%ecx
    movl mp1_list_head,%ecx
    cmpl $0,%ecx
    je not_valid
    movl mp1_list_head,%esi
loop_begin:
    xorl %edi,%edi
    movw LOCATION(%esi),%di
    # compare whether location is the same
    cmpw %bx,%di
    je find_it
    # store the last element
    movl %esi,%ecx
    movl NEXT(%esi),%esi
    # check whether list end
    cmpl $0,%esi
    je not_valid
    jmp loop_begin
not_valid:
    # can't find or not in range
    movl $-1,%eax
    popl %edi
    popl %esi
    popl %edx
    popl %ebx
    leave
    ret
find_it:
    # success return the address of this element
    movl %esi,%eax
    popl %edi
    popl %esi
    popl %edx
    popl %ebx
    leave
    ret
.end
