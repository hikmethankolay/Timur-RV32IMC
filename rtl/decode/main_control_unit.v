module main_control_unit (
    input  [6:0] opcode,
    input  [2:0] funct3,
    input  [6:0] funct7,
    input  [4:0] rs2_addr,
    output reg        Branch,
    output reg        MemRead,
    output reg        MemToReg,
    output reg [1:0]  ALUOp,
    output reg        MemWrite,
    output reg        ALUSrc,
    output reg        RegWrite,
    output reg        CSRWrite,
    output reg [1:0]  CSROp,
    output reg        IsECALL,
    output reg        IsEBREAK,
    output reg        IsMRET
);

    always @(*) begin
        case (opcode)
            7'b0110011: begin
                Branch = 1'b0;
                MemRead = 1'b0;
                MemToReg = 1'b0;
                ALUOp = 2'b10;
                MemWrite = 1'b0;
                ALUSrc = 1'b0;
                RegWrite = 1'b1;
                CSRWrite = 1'b0;
                CSROp = 2'b00;
                IsECALL = 1'b0;
                IsEBREAK = 1'b0;
                IsMRET = 1'b0;
            end
            
            7'b0010011: begin
                Branch = 1'b0;
                MemRead = 1'b0;
                MemToReg = 1'b0;
                ALUOp = 2'b10;
                MemWrite = 1'b0;
                ALUSrc = 1'b1;
                RegWrite = 1'b1;
                CSRWrite = 1'b0;
                CSROp = 2'b00;
                IsECALL = 1'b0;
                IsEBREAK = 1'b0;
                IsMRET = 1'b0;
            end

            7'b0000011: begin
                Branch = 1'b0;
                MemRead = 1'b1;
                MemToReg = 1'b1;
                ALUOp = 2'b00;
                MemWrite = 1'b0;
                ALUSrc = 1'b1;
                RegWrite = 1'b1;
                CSRWrite = 1'b0;
                CSROp = 2'b00;
                IsECALL = 1'b0;
                IsEBREAK = 1'b0;
                IsMRET = 1'b0;
            end
    
            7'b0100011: begin
                Branch = 1'b0;
                MemRead = 1'b0;
                MemToReg = 1'b0;
                ALUOp = 2'b00;
                MemWrite = 1'b1;
                ALUSrc = 1'b1;
                RegWrite = 1'b0;
                CSRWrite = 1'b0;
                CSROp = 2'b00;
                IsECALL = 1'b0;
                IsEBREAK = 1'b0;
                IsMRET = 1'b0;
            end

            7'b1100011: begin
                Branch = 1'b1;
                MemRead = 1'b0;
                MemToReg = 1'b0;
                ALUOp = 2'b01;
                MemWrite = 1'b0;
                ALUSrc = 1'b0;
                RegWrite = 1'b0;
                CSRWrite = 1'b0;
                CSROp = 2'b00;
                IsECALL = 1'b0;
                IsEBREAK = 1'b0;
                IsMRET = 1'b0;
            end

            7'b1101111: begin
                Branch = 1'b0;
                MemRead = 1'b0;
                MemToReg = 1'b0;
                ALUOp = 2'b00;
                MemWrite = 1'b0;
                ALUSrc = 1'b0;
                RegWrite = 1'b1;
                CSRWrite = 1'b0;
                CSROp = 2'b00;
                IsECALL = 1'b0;
                IsEBREAK = 1'b0;
                IsMRET = 1'b0;
            end

            7'b1100111: begin
                Branch = 1'b0;
                MemRead = 1'b0;
                MemToReg = 1'b0;
                ALUOp = 2'b00;
                MemWrite = 1'b0;
                ALUSrc = 1'b1;
                RegWrite = 1'b1;
                CSRWrite = 1'b0;
                CSROp = 2'b00;
                IsECALL = 1'b0;
                IsEBREAK = 1'b0;
                IsMRET = 1'b0;
            end

            7'b0110111: begin
                Branch = 1'b0;
                MemRead = 1'b0;
                MemToReg = 1'b0;
                ALUOp = 2'b00;
                MemWrite = 1'b0;
                ALUSrc = 1'b1;
                RegWrite = 1'b1;
                CSRWrite = 1'b0;
                CSROp = 2'b00;
                IsECALL = 1'b0;
                IsEBREAK = 1'b0;
                IsMRET = 1'b0;
            end

            7'b0010111: begin
                Branch = 1'b0;
                MemRead = 1'b0;
                MemToReg = 1'b0;
                ALUOp = 2'b00;
                MemWrite = 1'b0;
                ALUSrc = 1'b1;
                RegWrite = 1'b1;
                CSRWrite = 1'b0;
                CSROp = 2'b00;
                IsECALL = 1'b0;
                IsEBREAK = 1'b0;
                IsMRET = 1'b0;
            end
            
            7'b0001111: begin
                Branch   = 1'b0;
                MemRead  = 1'b0;
                MemToReg = 1'b0;
                ALUOp    = 2'b00;
                MemWrite = 1'b0;
                ALUSrc   = 1'b0;
                RegWrite = 1'b0;
                CSRWrite = 1'b0;
                CSROp    = 2'b00;
                IsECALL  = 1'b0;
                IsEBREAK = 1'b0;
                IsMRET   = 1'b0;
            end

            7'b1110011: begin
                // default all to 0 first
                Branch   = 1'b0;
                MemRead  = 1'b0;
                MemToReg = 1'b0;
                ALUOp    = 2'b00;
                MemWrite = 1'b0;
                ALUSrc   = 1'b0;
                RegWrite = 1'b0;
                CSRWrite = 1'b0;
                CSROp    = 2'b00;
                IsECALL  = 1'b0;
                IsEBREAK = 1'b0;
                IsMRET   = 1'b0;

                case (funct3)
                    3'b000: begin
                        if (funct7 == 7'b0011000) begin
                            IsMRET = 1'b1;
                        end else if (rs2_addr == 5'b00001) begin
                            IsEBREAK = 1'b1;
                        end else begin
                            IsECALL = 1'b1;
                        end
                    end

                    3'b001: begin
                        CSRWrite = 1'b1;
                        CSROp    = 2'b00;
                        RegWrite = 1'b1;
                    end

                    3'b010: begin
                        CSRWrite = 1'b1;
                        CSROp    = 2'b01;
                        RegWrite = 1'b1;
                    end

                    3'b011: begin
                        CSRWrite = 1'b1;
                        CSROp    = 2'b10;
                        RegWrite = 1'b1;
                    end

                    3'b101: begin
                        CSRWrite = 1'b1;
                        CSROp    = 2'b00;
                        RegWrite = 1'b1;
                    end

                    3'b110: begin
                        CSRWrite = 1'b1;
                        CSROp    = 2'b01;
                        RegWrite = 1'b1;
                    end

                    3'b111: begin
                        CSRWrite = 1'b1;
                        CSROp    = 2'b10;
                        RegWrite = 1'b1;
                    end

                    default: begin
                        // unknown funct3 — all outputs stay 0
                    end
                endcase
            end

            default: begin
                Branch = 1'b0;
                MemRead = 1'b0;
                MemToReg = 1'b0;
                ALUOp = 2'b00;
                MemWrite = 1'b0;
                ALUSrc = 1'b0;
                RegWrite = 1'b0;
                CSRWrite = 1'b0;
                CSROp = 2'b00;
                IsECALL = 1'b0;
                IsEBREAK = 1'b0;
                IsMRET = 1'b0;
            end 
        endcase
    end

endmodule