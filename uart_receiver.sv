module uart_receiver #(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD_RATE = 38_400
)(
    input logic clk,
    input logic reset_n,
    input logic rx,
    output logic [7:0] data,
    output logic valid,
    output logic error
);
    localparam BIT_PERIOD = CLK_FREQ / BAUD_RATE;
    
    logic [3:0] state = 0;
    logic [15:0] counter = 0;
    logic [2:0] bit_index = 0;
    logic [7:0] shift_reg = 0;
    
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= 0;
            valid <= 0;
            error <= 0;
        end else begin
            valid <= 0;
            error <= 0;
            
            case (state)
                0: begin // Ожидание стартового бита
                    if (!rx) begin
                        state <= 1;
                        counter <= BIT_PERIOD / 2;
                    end
                end
                
                1: begin // Центр стартового бита
                    if (counter == 0) begin
                        if (!rx) begin
                            state <= 2;
                            counter <= BIT_PERIOD;
                            bit_index <= 0;
                        end else begin
                            state <= 0;
                            error <= 1;
                        end
                    end else begin
                        counter <= counter - 1;
                    end
                end
                
                2: begin // Приём битов данных
                    if (counter == 0) begin
                        shift_reg[bit_index] <= rx;
                        if (bit_index == 7) begin
                            state <= 3;
                        end else begin
                            bit_index <= bit_index + 1;
                        end
                        counter <= BIT_PERIOD;
                    end else begin
                        counter <= counter - 1;
                    end
                end
                
                3: begin // Стоповый бит
                    if (counter == 0) begin
                        if (rx) begin
                            data <= shift_reg;
                            valid <= 1;
                        end else begin
                            error <= 1;
                        end
                        state <= 0;
                    end else begin
                        counter <= counter - 1;
                    end
                end
            endcase
        end
    end
endmodule
