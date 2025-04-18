module gmsk_modulator (
    input wire clk,
    input wire reset_n,
    input wire [1:0] data_in, // Входные биты, 2-битный уровень для GMSK
    output reg gmsk_out,       // Выход GMSK модулированной сигнала
    output reg ready          // Индикатор готовности
);

    // Параметры для GMSK
    localparam  BD_RATE      = 38400;              // Скорость передачи
    localparam  CLK_FREQ     = 50000000;           // Частота тактового сигнала
    localparam  SAMPLES_PER_BIT = CLK_FREQ / BD_RATE;

    reg [15:0] counter;
    reg [1:0] prev_data;
    
    // Счетчик для генерации GMSK
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            counter <= 0;
            gmsk_out <= 0;
            ready <= 0;
        end
        else begin
            if (counter < SAMPLES_PER_BIT - 1) begin
                counter <= counter + 1;
                ready <= 0;
            end
            else begin
                counter <= 0;
                if (data_in != prev_data) begin
                    gmsk_out <= ~gmsk_out; // Простая инверсия, чтобы имитировать модуляцию
                end
                ready <= 1; // Данные готовы для передачи
                prev_data <= data_in; // Запоминаем предыдущее значение
            end
        end
    end
endmodule
