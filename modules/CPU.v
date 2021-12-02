module CPU (
    MAR,
    MBR_in,
    MBR_out,
    Mem_EN,
    Mem_CS, // control signal 0 for read, 1 for write
    clk
);

// addresses are 8 bits
output reg [7:0] MAR; // Memory Address Register

// Memory Buffer Registers (words are 24 bits)
output reg [23:0] MBR_out;
input wire [23:0] MBR_in;

// program counter, stack pointer register
reg [7:0] PC, SP, Status_Reg;

// status register parameters
parameter 
    // suppose Status register [ 2 ] is the zero flag
    zero_flag = 2,

    // and     Status register [ 3 ] is a flag for indirect operand fetch state (0 for fetch_pointer, 1 for fetch_oprand_using_pointer)
    indirect_flag = 3;

// Instruction register (instructions are 19 bits)
reg [18:0] IR;

// register file contains 16 registers each is 24 bits
reg [23:0] Registar_File [0:15];

// accumlator
reg [23:0] AC;

// clock
input wire clk;

// memory control bus (memory enable, memory control signal)
output reg Mem_EN, Mem_CS;

// 3 bits since we have 8 states TODO
reg [2:0] state;

// states
parameter 
    copy_pc_to_mar = 0,
    fetch_instruction = 1,
    decode_instruction = 2, //and determine addressing mode
    fetch_operand = 3,
    copy_pointer_to_MAR=4,
    execute = 5;

// memory operations
parameter 
    mem_read = 0,
    mem_write = 1;

// addressing modes
parameter 
    direct = 3'b000,
    indirect = 3'b001,
    immediate = 3'b010,
    register = 3'b011,
    stack = 3'b100;

// instruction fields
parameter 
    opcode_field_msb = 18,
    opcode_field_lsb = 15,

    register_field_msb = 14,
    register_field_lsb = 11,

    operand_feild_msb = 10,
    operand_feild_lsb = 3,

    addressing_mode_field_msb = 2,
    addressing_mode_field_lsb = 0;

// opcodes
parameter 

    // 0011 LOAD Ri, M; loads the contents of memory location M into Ri, where Ri is the number of the register (Direct Addressing)
    // 0011 LOAD Ri, 8; set Ri to 8 (Immediate Addressing)
    // 0011 LOAD Ri, [[M]]; use the contents of memory location M as a pointer to the operand then load it to Ri, (InDirect Addressing)
    load = 4'b0011,
    
    // 1011 STORE Ri, M; stores the contents of Ri into memory location M. (Direct Addressing)
    store = 4'b1011,

    // 0111 ADD Ri, M; adds the contents of memory location M to the contents of Ri, and stores the result in Ri. (Direct Addressing)
    // 0111 ADD Ri, Rj; Ri = Ri + Rj (Register Addressing)
    add = 4'b0111,

    // 1100 JUMP M; unconditional jump to location M in memory. (Direct Addressing)
    jump = 4'b1100,

    // 1101 CMP Ri, Rj; compare two registers and set zero flag if Ri = Rj (Register Addressing)
    cmp = 4'b1101,

    // 1110 SL Ri, C; applying logical shift left operation to Ri, such that, C is constant (Immediate Addressing) 
    sl = 4'b1110,

    // 1111 SR Ri, C; applying logical shift right operation to Ri,C is constant (Immediate Addressing)
    sr = 4'b1111,

    // 0000 PUSH Ri; Add Ri to the top of the stack (Stack Addressing)
    push = 4'b0000,

    // 0001 POP Ri; Ri = top of the stack then clear the top of the stack (Stack Addressing)
    pop = 4'b0001;
    

initial begin

    $display("(%0t) > initializing CPU ...", $time);
    
    $dumpfile("waves.vcd");
    $dumpvars(0, Registar_File[1], Registar_File[2]);

    PC=20; // to start the sample program (defined in the memory module from address 10)
    SP=8'b0;
    Status_Reg=8'b0;
    state=0;
    Mem_EN=0;
    Mem_CS=0;

end

always @(posedge clk ) begin

    #2; // just to organize the output of display statements

    case (state)

        // 0: get instruction address from PC and put it in MAR (and send a read signal to the memory)
        copy_pc_to_mar: begin

            $display("\n ~~~~~~~~~~~~~~ New Instruction Cycle ~~~~~~~~~~~~~~ \n");

            #1 $display("(%0t) CPU > get_instruction_addr, PC=%0d", $time, PC);

            MAR <= PC;
            Mem_EN=1;
            Mem_CS=mem_read;

            Status_Reg[indirect_flag] = 0;
            
            state=fetch_instruction;
        end

        // 1: finish fetching instruction from MBR to Instruction Registar
        fetch_instruction: begin

            $display("(%0t) CPU > fetch_instruction", $time);

            $display("(%0t) CPU > MBR_in = %0b", $time, MBR_in);

            Mem_EN=0;

            IR <= MBR_in[18:0]; // reading instruction to Instruction register
            PC <= PC + 1; //increase program counter to point to the next instruction
            state=decode_instruction;
        end

        //////////////////////////////////////////////////////////

        //////////////////////////////////////////////////////////

        // 2: decode instruction ( prepare to fetch operand , copy operand address from instruction to MAR and send read CS)
        decode_instruction: begin

            $display("(%0t) CPU > IR = %0b", $time, IR);

            $display("(%0t) CPU > decode_instruction", $time);

            #1;

            case (IR[addressing_mode_field_msb:addressing_mode_field_lsb]) // determine addressing mode

                direct : begin
                    $display("(%0t) CPU > decode_instruction : direct, %0d:%0d is %0b >> %0d >> %0h", $time, operand_feild_msb, operand_feild_lsb, IR[operand_feild_msb:operand_feild_lsb], IR[operand_feild_msb:operand_feild_lsb], IR[operand_feild_msb:operand_feild_lsb] );
                    MAR <= IR [operand_feild_msb:operand_feild_lsb]; // copy operand from the instruction (memory address of operand)
                    state=fetch_operand;
                end
            
                indirect : begin
                    $display("(%0t) CPU > decode_instruction : indirect ", $time);
                    MAR <= IR [operand_feild_msb:operand_feild_lsb]; // copy operand from the instruction (memory address of operand pointer)
                    state=fetch_operand;
                    Status_Reg[indirect_flag] = 0;
                end

                immediate : begin
                    $display("(%0t) CPU > decode_instruction : immediate ", $time);
                    state=execute;
                end

                stack : begin
                    $display("(%0t) CPU > decode_instruction : stack ", $time);

                    case (IR[opcode_field_msb:opcode_field_lsb]) // determine operation based on opcode
                        
                        // 0000 PUSH Ri; Add Ri to the top of the stack (Stack Addressing)
                        push : begin
                            MAR <= SP + 1;
                            state=execute;
                        end

                        // 0001 POP Ri; Ri = top of the stack then clear the top of the stack (Stack Addressing)
                        pop : begin
                            MAR <= SP;
                            state=fetch_operand;
                        end

                    endcase

                    
                end

                register : begin
                    $display("(%0t) CPU > decode_instruction : register ", $time);
                    state=execute;
                end
                
                // for immediate, register, stack there is nothing to fetch so we jump to state = TODO
                
            endcase
        end

        // 3: fetch direct operand / or fetch pointer if indirect
        fetch_operand: begin

            // fetch whats address is in MAR , and save it in MBR_in

            $display("(%0t) CPU > fetch_operand", $time);

            Mem_EN=1;
            Mem_CS=mem_read; // copy operand (or it's pointer) from memory address at MAR to MBR

            if (IR[addressing_mode_field_msb:addressing_mode_field_lsb] == indirect && !Status_Reg[indirect_flag]) begin
                state=copy_pointer_to_MAR;
            end else begin
                state=execute;

            end

        end

        // 4: fetch operand from pointer
        copy_pointer_to_MAR: begin

            $display("(%0t) CPU > copy_pointer_to_MAR", $time);

            MAR <= MBR_in[18:0]; // copy operand from the instruction (memory address of operand)
            Status_Reg[indirect_flag] = 1;
            state=fetch_operand;
            
        end

        // 5: execute
        execute: begin

            $display("(%0t) CPU > execute", $time);

            Mem_EN=0;
            
            case (IR[opcode_field_msb:opcode_field_lsb]) // determine operation based on opcode
                
                load : begin

                    case (IR[addressing_mode_field_msb:addressing_mode_field_lsb]) // determine addressing mode

                        // 0011 LOAD Ri, M; loads the contents of memory location M into Ri, where Ri is the number of the register (Direct Addressing)
                        direct : begin
                            Registar_File[IR[register_field_msb:register_field_lsb]] <= MBR_in; // copy operand from MBR to Ri                     
                        end
                        
                        // 0011 LOAD Ri, [[M]]; use the contents of memory location M as a pointer to the operand then load it to Ri, (InDirect Addressing)
                        indirect : begin
                            Registar_File[IR[register_field_msb:register_field_lsb]] <= MBR_in; // copy operand from MBR to Ri
                        end
                        
                        // 0011 LOAD Ri, 8; set Ri to 8 (Immediate Addressing)
                        immediate : begin
                            Registar_File[IR[register_field_msb:register_field_lsb]] <= IR[operand_feild_msb:operand_feild_lsb]; // copy operand from instruction to Ri
                        end
                
                    endcase

                end

                // 1011 STORE Ri, M; stores the contents of Ri into memory location M. (Direct Addressing)
                store : begin
                    // copy Ri to MBR_out and send enable, write signals to the memory to store it
                    MBR_out <= Registar_File [ IR[register_field_msb:register_field_lsb] ];
                    Mem_EN=1;
                    Mem_CS=mem_write;
                end
                

                add : begin

                    case (IR[addressing_mode_field_msb:addressing_mode_field_lsb]) // determine addressing mode

                        // 0111 ADD Ri, M; adds the contents of memory location M to the contents of Ri, and stores the result in Ri. (Direct Addressing)
                        direct : begin
                            Registar_File[IR[register_field_msb:register_field_lsb]] <= Registar_File[IR[register_field_msb:register_field_lsb]] + MBR_in;
                        end
                        
                        // 0111 ADD Ri, Rj; Ri = Ri + Rj (Register Addressing)
                        register : begin
                            Registar_File[IR[register_field_msb:register_field_lsb]] <= Registar_File[IR[register_field_msb:register_field_lsb]] + Registar_File[IR[operand_feild_msb:operand_feild_lsb]];
                        end
                
                    endcase
                end
                
                // 1100 JUMP M; unconditional jump to location M in memory. (Direct Addressing)
                jump : begin
                    PC <= IR[operand_feild_msb:operand_feild_lsb];
                end

                // 1101 CMP Ri, Rj; compare two registers and set zero flag if Ri = Rj (Register Addressing)
                cmp : begin
                    
                    if (Registar_File[IR[register_field_msb:register_field_lsb]] == Registar_File[IR[operand_feild_msb:operand_feild_lsb]]) begin
                        Status_Reg[zero_flag] = 1;
                    end else begin
                        Status_Reg[zero_flag] = 0;
                    end
                end
                
                // 1110 SL Ri, C; applying logical shift left operation to Ri, such that, C is constant (Immediate Addressing) 
                sl : begin
                    Registar_File[IR[register_field_msb:register_field_lsb]] <= Registar_File[IR[register_field_msb:register_field_lsb]] << IR[operand_feild_msb:operand_feild_lsb];
                end

                // 1111 SR Ri, C; applying logical shift right operation to Ri,C is constant (Immediate Addressing)
                sr : begin
                    Registar_File[IR[register_field_msb:register_field_lsb]] <= Registar_File[IR[register_field_msb:register_field_lsb]] >> IR[operand_feild_msb:operand_feild_lsb];
                end

                // 0000 PUSH Ri; Add Ri to the top of the stack (Stack Addressing)
                push : begin
                    MBR_out <= Registar_File[IR[register_field_msb:register_field_lsb]];
                    Mem_EN=1;
                    Mem_CS=mem_write;
                    SP <= SP + 1;
                end

                // 0001 POP Ri; Ri = top of the stack then clear the top of the stack (Stack Addressing)
                pop : begin
                    Registar_File[IR[register_field_msb:register_field_lsb]] <= MBR_in;
                    SP <= SP - 1;
                end

                default: begin
                    Mem_EN=0;
                    state = 10; // TODO raise some exception (unknown opcode)
                    $display("(%0t) Unknown Opcode !", $time);
                end
                    
            endcase

            state = 0;

        end

    endcase
end

endmodule