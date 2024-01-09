# mp1.S - missile-command version
# Good luck, and have fun!

.data
	
    # Constants for accessing the fields of a struct missile, 
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32

    # Character to draw for an explosion - '@'

	EXPLOSION = 64


# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs

prev_node:		.long 0x0	# globl var to store prev node of curr node in linked list

.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1), %edx
		movb    %cl, (%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks:
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:
		pushl %ebp
		movl %esp, %ebp
		# callee - saving registers
		pushl %ebx
		pushl %esi
		pushl %edi

		# Tasklet first operation
		movl mp1_missile_list, %edx  # loading edx with head of linked list
		xorl %ecx, %ecx
		movl $0, %ecx

		traverse_linkedlist:  # walking through linked list of missile nodes
		cmpl $0, %edx
		je bases_drawing  # if curr == NULL, move to drawing bases
		jne continue_traversal
		continue_traversal:   
		pushl %ecx
		pushl %edx
		call update_missiles
		add $8, %esp		# pop off curr and prev off stack

		movl %edx, %ecx

		cmpl $0, %edx		# if curr == NULL, end of linked list reached, move on to drawing base
		je bases_drawing

		movl NEXT(%edx), %edx
		jmp traverse_linkedlist

		# second operation - drawing the bases in text video location
		bases_drawing:
		movl $4, %edi	# 5 chars per base
		movl $2, %esi	# 3 bases
		movl base_alive, %edx
		sall $8, %edx	# removing zero padding in base_alive
		movl $24, %eax
		imull $80, %eax, %eax
		imull $2, %eax, %eax	# 2 bytes per char
		addl $116, %eax

		count_bases:
		cmpl $0, %esi		# checking if all three bases are drawn
		jl crosshair_redrawing	# if bases drawn, move on to drawing crosshairs
		jmp count_base_continue
		count_base_continue:
		cmpl $0, %edx	# checking if current base is alive or destroyed
		jge destroyed_base
		jmp count_base_continue_2
		count_base_continue_2:
		movl $base_pic, %ebx	# loading alive base chars
		jmp alive_base

		destroyed_base:
		movl $dead_base_pic, %ebx	# loading destroyed base chars

		alive_base:
		movl $4, %edi		# done again to ensure edi has correct val to count chars
		jmp drawing_character_loop

		drawing_character_loop:
		cmpl $0, %edi		# if zero then all chars for current base have been drawn
		jl character_loop_finished
		movl (%ebx), %ecx

		pushl %edx	# caller-saving edx since it is clobbered by mp1_poke
		call mp1_poke
		popl %edx

		incl %eax	# updating video memory offset
		incl %eax
		incl %ebx	# moving to next char in base pic
		decl %edi	# decrementing chars of current base pic left to be drawn
		jmp drawing_character_loop

		# current base drawn, recalculating offset
		character_loop_finished:
		subl $48, %eax		# offset for drawing bases
		sall $8, %edx
		decl %esi
		jmp count_bases

		# third operation - redrawing the crosshairs
		crosshair_redrawing:
		imul $160, crosshairs_y, %eax	# setting offset for video memory
		movl crosshairs_x, %edi
		shll $1, %edi
		addl %edi, %eax
		movb $43, %cl	# char to draw crosshair

		# caller-saving edx since it's clobbered by mp1_poke
		pushl %edx
		call mp1_poke
		popl %edx

		# callee-teardown
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret


# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function 
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:
		movl 8(%esp), %eax
		cmpl $4, %eax 	# checking if cmd > 4
		ja invalid_cmd
		cmpl $0, %eax	# checking if cmd < 0
		jl invalid_cmd
		
		jmp *jumptable(, %eax, 4)		# no need to caller setup, accesses ioctls by assembly linkage
		jumptable:
		.long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame

		invalid_cmd:	# indicate invalid cmd for jumptable
		movl $-1, %eax
		ret
# ----------------- Functions private to this file -------------------

# update missile
# called from tasklet to update misssile, continue missile moving and check exploding status
# Inputs   : struct to missile pointer 
# Outputs  : updating missile status
# Registers: Standard C calling convention (except mp1_poke)
update_missiles:
		pushl %ebp
		movl %esp, %ebp
		# callee - saving registers
		pushl %ebx
		pushl %esi
		pushl %edi

		movl 8(%ebp), %edx	# loading curr missile struct
		# cmpl $0, %edx
		# je callee_teardown_update_missile
		
		movl X(%edx), %esi	# loading x-coords in esi
		movl Y(%edx), %edi	# loading y-coords in edi

		# arithmetic right for correct sign extension
		sarl $16, %esi
		sarl $16, %edi

		# checking if missile is in screen bounds
		cmpl $0, %esi
		jl explode_decrement
		cmpl $79, %esi		# RECHECK BOUNDS	
		jg explode_decrement
		cmpl $0, %edi
		jl explode_decrement
		cmpl $24, %edi
		jg explode_decrement

		cmpl $0, EXPLODED(%edx)		# checking if missile exploded
		jne exploding_now
		je destination_reached_check
		destination_reached_check:
		cmpl %esi, DEST_X(%edx)
		jne continue_moving
		cmpl %edi, DEST_Y(%edx)
		jne continue_moving
		je exploding_now

		exploding_now:
		pushl %ecx	# caller save before missile_explode
		pushl %edx

		pushl %edx	# pushing arg - pointer to missile struct to stack
		call missile_explode
		addl $4, %esp

		popl %edx	# caller teardown after missile_explode
		popl %ecx

		cmpl $0, %eax	# if game status has changed, user must be notified
		jne notify_user
		je explode_decrement

		notify_user:	
		pushl %eax		# caller - buildup for call to mp1_notify_user
		pushl %ecx
		pushl %edx
		call mp1_notify_user
		popl %edx		# caller - teardown for call to mp1_notify_user
		popl %ecx
		popl %eax

		explode_decrement:
		decl EXPLODED(%edx)		# decrementing exploded field of current missile

		# erasing missile's current position 
		imul $160, %edi, %eax	# setting video memory offset
		movl %esi, %ebx
		shll $1, %ebx
		addl %ebx, %eax
		movb $32, %cl

		pushl %edx	# caller-saving edx since it is clobbered by mp1_poke
		call mp1_poke
		popl %edx

		cmpl $0, EXPLODED(%edx)		# if exploded field == 0, remove missile, else draw explosion char
		jg draw_explode_char
		je mp1_missile_remove

		draw_explode_char:	# drawing explosion chars on screen
		imul $160, %edi, %eax
		movl %esi, %ebx
		shll $1, %ebx
		addl %ebx, %eax
		movb $EXPLOSION, %cl

		pushl %edx	# caller-saving edx since it is clobbered by mp1_poke
		call mp1_poke
		popl %edx

		jmp callee_teardown_update_missile

		continue_moving:
		# missile still moving
		# remove old missile chars and update with new position
		imul $160, %edi, %eax
		movl %esi, %ebx
		shll $1, %ebx
		addl %ebx, %eax
		movb $32, %cl 

		pushl %edx	# caller-saving edx since it is clobbered by mp1_poke
		call mp1_poke
		popl %edx

		# old chars of missile erased, drawing new, updated position
		movl VX(%edx), %esi
		addl X(%edx), %esi
		movl %esi, X(%edx)	# x-coords updating
		sarl $16, %esi

		movl VY(%edx), %edi
		addl Y(%edx), %edi
		movl %edi, Y(%edx)	# y-coords updating
		sarl $16, %edi

		# draw current missile (with updated coords)
		imul $160, %edi, %eax	# setting offset for video memory
		movl %esi, %ebx
		shll $1, %ebx
		addl %ebx, %eax
		movb C(%edx), %cl		# char for current missile 

		pushl %edx	# caller-saving edx since it is clobbered by mp1_poke
		call mp1_poke
		popl %edx
		jmp callee_teardown_update_missile

		mp1_missile_remove:
		# storing prev, curr, next
		# curr = edx
		movl 8(%ebp), %edx
		# prev = ecx
		movl 12(%ebp), %ecx
		# next = eax
		movl NEXT(%edx), %eax

		cmpl mp1_missile_list, %edx		# if missile head points to null we are at head node
		je is_head_node
		jne not_head

		is_head_node:
		movl %eax, mp1_missile_list		# saving current next as new head before deleting curr
		jmp free_node

		not_head:
		cmpl $0, %eax	# now checking if it's the last node
		je is_last_node
		jne not_last

		not_last:	# not head, not last node, somewhere in the middle
		movl %eax, NEXT(%ecx)	# updating prev -> next with curr -> next
		jmp free_node

		is_last_node:
		movl $0, NEXT(%ecx)
		jmp free_node

		free_node:
		pushl %eax	# caller-save before mp1_free call
		pushl %edx
		pushl %ecx

		pushl %edx  # pushing arg for mp1_free to stack
		call mp1_free
		addl $4, %esp

		popl %ecx	# caller-teardown for mp1_free call
		popl %edx
		popl %eax

		movl %ecx, %edx		# updating prev to curr
		cmpl mp1_missile_list, %eax
		je sanity_head_check
		jmp callee_teardown_update_missile

		sanity_head_check:		# RECHECK DEBUG
		movl %eax, %edx
		jmp callee_teardown_update_missile

		callee_teardown_update_missile:
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

# int mp1_ioctl_startgame(unsigned long arg, unsigned int cmd)
# to initialize all game variables - local and global 
# Inputs   : cmd for jump table and arg to pass to the ioctl that is called from jump table
# Outputs  : none but all variables initialized
# Registers: Standard C calling convention
mp1_ioctl_startgame:    # intializing variables
		pushl %ebp
		movl %esp, %ebp
		# callee - saving registers
		pushl %ebx
		pushl %esi
		pushl %edi

		jmp initialize_vars

		initialize_vars:		# initializing vars before game starts
		movl $0, mp1_missile_list
		movl $0, mp1_score
		movl $40, crosshairs_x    # setting crosshairs to starting point (40, 12)
		movl $12, crosshairs_y
		movl $0x00FFFFFF, base_alive   # first 3 bits are non zero, 4th bit zero for padding
		jmp callee_teardown_startgame

		callee_teardown_startgame:
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

# int mp1_ioctl_addmissile(struct missile *user_missile)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : missile pointer to add  to list
# Outputs  : status updated in eax after dynamic memory allocation and copy_to_user
# Registers: Standard C calling convention
mp1_ioctl_addmissile: 
		pushl %ebp
		movl %esp, %ebp
		# callee - saving registers
		pushl %ebx
		pushl %esi
		pushl %edi
		jmp read_new_missile

		read_new_missile:
		movl 8(%ebp), %ebx # reading missile in ebx

		pushl %edx  # caller - save before malloc call
		pushl %ecx

		pushl $36    # size = 36 bytes of dynamically allocated memory (malloc args)
		call mp1_malloc
		addl $4, %esp	# pop malloc args off stack

		popl %ecx     # caller - teardown after malloc call
		popl %edx 

		cmpl $0, %eax	# checking malloc success status
		je return_negative_1_addmissile  # if memory allocation unsuccessful, then ptr has NULL 
		jne copy_from_user_addmissile

		copy_from_user_addmissile:
		pushl %eax		# caller-saving before mp1_from_user call
		pushl %edx
		pushl %ecx

		# pushing args for copy_from_user to stack
		pushl $36
		pushl %ebx
		pushl %eax
		call mp1_copy_from_user
		add $12, %esp	# pop copy_to_user args off stack

		popl %ecx		# caller - teardown after copy_to_user call
		popl %edx

		cmpl $0, %eax		# checking if copy_from_user was successful
		je update_next_missile
		jne return_negative_1_addmissile_free
		

		update_next_missile:	# redirecting pointers to add new missile at head
		popl %eax
		movl mp1_missile_list, %edx
		movl %edx, NEXT(%eax)			# curr head now becomes the second node in list 
		movl %eax, mp1_missile_list		# storing new head
		jmp indicate_success

		indicate_success:		# load eax with 0 to indicate success
		movl $0, %eax 
		jmp end_addmissile

		return_negative_1_addmissile:	# malloc call failed
		movl $-1, %eax
		jmp end_addmissile

		return_negative_1_addmissile_free:	# if copy_to_user is unsucessful
		popl %eax

		pushl %eax # pushing argument to call mp1_free
		call mp1_free	# freeing the block of memory allocated by malloc
		addl $4, %esp

		movl $-1, %eax
		jmp end_addmissile

		end_addmissile:
		# callee-teardown
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

# int mp1_ioctl_movexhairs(unsigned long xhair_delta_packed)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : xhair_delta - lower 16 bits is x position, upper 16 bits is y position
# Outputs  : crosshair position updated
# Registers: Standard C calling convention
mp1_ioctl_movexhairs:
		pushl %ebp
		movl %esp, %ebp
		# callee - saving registers
		pushl %ebx
		pushl %esi
		pushl %edi

		# erasing old crosshairs
		imul $160, crosshairs_y, %eax	# setting offset in video memory
		movl crosshairs_x, %ebx
		shll $1, %ebx
		addl %ebx, %eax
		movb $32, %cl	# blank char

		pushl %edx  # caller-saving edx since it is clobbered
		call mp1_poke
		popl %edx

		movl 8(%ebp), %ebx
		xorl %esi, %esi
		movw %bx, %si 	# loading lower 16 bits into esi
		shll $16, %esi
		sarl $16, %esi
		sarl $16, %ebx	# upper 16 bits into ebx

		# checking x bounds of grid
		check_x_bound:
		addl crosshairs_x, %esi
		cmpl $0, %esi
		jl lower_x_bound
		cmpl $79, %esi
		jg upper_x_bound
		movl %esi, crosshairs_x		# if within bounds update x-coords of crosshairs
		jmp check_y_bound

		lower_x_bound:		# lower x bound check
		movl $0, crosshairs_x
		jmp check_y_bound

		upper_x_bound:		# upper x bound check
		movl $79, crosshairs_x
		jmp check_y_bound

		# checking y bounds of grid
		check_y_bound:
		addl crosshairs_y, %ebx
		cmpl $0, %ebx
		jl lower_y_bound
		cmpl $24, %ebx
		jg upper_y_bound
		movl %ebx, crosshairs_y		# if within bounds update y-coords of crosshairs
		jmp crosshairs_draw

		lower_y_bound:		# lower y bound check
		movl $0, crosshairs_y
		jmp crosshairs_draw

		upper_y_bound:		# upper y bound check
		movl $24, crosshairs_y
		jmp crosshairs_draw

		# redraw crosshairs at updated location 
		crosshairs_draw:   # drawing crosshairs
		imul $160, crosshairs_y, %eax	# setting offset in video memory
		movl crosshairs_x, %edi
		shll $1, %edi
		addl %edi, %eax
		movb $43, %cl          # char to draw crosshair

		# caller-saving edx since it's clobbered by mp1_poke
		pushl %edx
		call mp1_poke
		popl %edx

		# ret 0
		movl $0, %eax	# move crosshairs has to always be successful

		# callee-teardown
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

# int mp1_ioctl_getstatus(unsigned long*  user status)
# This is a dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : user_status to write status of bases and mp1_score
# Outputs  : game status updated
# Registers: Standard C calling convention
mp1_ioctl_getstatus:
		pushl %ebp
		movl %esp, %ebp
		# callee - saving registers
		pushl %ebx
		pushl %esi
		pushl %edi

		movl 8(%ebp), %ebx
		xorl %ecx, %ecx  # loop counter
		xorl %esi, %esi  # reg for bit manipulation
		movl base_alive, %edi  # base_alive array in edi
		shll $8, %edi   # logical left shift to remove extra padding bit
		jmp loop_getstatus

		# retrieve status for each base and update bits at *user_status
		loop_getstatus:
		cmpl $3, %ecx	# counting number of bases
		jge loop_ended
		cmpl $0, %edi	# if edi < 0 then base dead because base_alive loaded with 0x00FFFFFF
		jge base_is_destroyed
		jl base_is_alive

		base_is_alive:
		incl %esi
		shll $1, %esi   # updating status of base to alive
		shll $8, %edi   # moving to next base in base_alive array
		incl %ecx		# incrementing loop counter
		jmp loop_getstatus

		base_is_destroyed:
		shll $1, %esi  # updating status of base to destroyed
		shll $8, %edi   # moving to next base in base_alive array
		incl %ecx		# incrementing loop counter
		jmp loop_getstatus

		loop_ended:
		shll $15, %esi
		movl mp1_score, %edi  # storing score in lower 16 bits
		movw %di, %si   # lower 16 bits stored esi
		pushl %esi

		# setting up call to copy_to_user
		movl %esp, %eax  # esp holds *from => storing it in eax which will be pushed to stack

		pushl %edx   # caller - buildup for copy_to_user
		pushl %ecx

		pushl $4 # = n
		pushl %eax # = *from
		pushl %ebx  # = *to
		call mp1_copy_to_user
		addl $12, %esp  # updating stack pointer

		popl %ecx	# caller - teardown for copy_to_user
		popl %edx

		popl %esi

		# checking if copy_to_user was successful
		cmpl $0, %eax
		je copy_to_user_success
		jmp copy_to_user_failed

		copy_to_user_failed:
		movl $-1, %eax		# load -1 in eax for failure
		jmp end_ioctl_getstatus

		copy_to_user_success:
		movl $0, %eax		# load -1 in eax for success
		jmp end_ioctl_getstatus

		end_ioctl_getstatus:
		# callee-teardown
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

# int mp1_ioctl_endgame(ending the game and freeing variables)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : None
# Outputs  : freeing all nodes in the linked list
# Registers: Standard C calling convention
mp1_ioctl_endgame:
		pushl %ebp
		movl %esp, %ebp
		# callee - saving registers
		pushl %ebx
		pushl %esi
		pushl %edi

		free_nodes:
		cmpl $0, mp1_missile_list  # checking if head == NULL
		jne free_next_node   # if head != NULL move to next node and free current head
		je all_nodes_freed

		free_next_node:
		movl mp1_missile_list, %esi	# curr head
		movl NEXT(%esi), %edi	# saving curr_head -> next
		movl %edi, mp1_missile_list  # updating with new head

		pushl %eax		# caller - save for mp1_free call
		pushl %edx
		pushl %ecx

		pushl %esi		# pushing curr head arg for mp1_free
		call mp1_free
		addl $4, %esp	# pop off arg for mp1_free
		# popl %esi
		jmp caller_teardown_free_node

		caller_teardown_free_node:
		popl %ecx		# caller - teardown mp1_free
		popl %edx
		popl %eax
		jmp free_nodes	# move on to next node

		all_nodes_freed:
		popl %edi		# callee-teardown
		popl %esi
		popl %ebx
		leave
		ret

