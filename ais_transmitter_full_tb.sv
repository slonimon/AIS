`timescale 1ns / 1ps

module ais_transmitter_full_tb;

    // Параметры тестирования
    localparam CLK_PERIOD = 20; // 50 MHz
    localparam UART_PERIOD = 2604; // 38400 бод (1/38400 ≈ 26.04 мкс)
    
    // Сигналы
    logic clk = 0;
    logic reset_n = 0;
    logic uart_rx = 1;
    logic ais_tx;
    logic led_ready;
    logic led_tx_active;
    
    // Экземпляр тестируемого модуля
    ais_transmitter_full dut (
        .clk(clk),
        .reset_n(reset_n),
        .uart_rx(uart_rx),
        .ais_tx(ais_tx),
        .led_ready(led_ready),
        .led_tx_active(led_tx_active)
    );
    
    // Генератор тактового сигнала
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // Задача для отправки UART байта
    task send_uart_byte(input logic [7:0] data);
        // Стартовый бит
        uart_rx = 0;
        #UART_PERIOD;
        
        // Биты данных
        for (int i = 0; i < 8; i++) begin
            uart_rx = data[i];
            #UART_PERIOD;
        end
        
        // Стоповый бит
        uart_rx = 1;
        #UART_PERIOD;
    endtask
    
    // Инициализация
    initial begin
        // Сброс
        #100;
        reset_n = 1;
        #100;
        
        // Тест 1: Отправка простого сообщения
        $display("Тест 1: Отправка простого сообщения");
        
        // Пример данных AIS (32 байта)
        send_uart_byte(8'h01); // Тип сообщения
        send_uart_byte(8'h12); // MMSI
        send_uart_byte(8'h34);
        send_uart_byte(8'h56);
        send_uart_byte(8'h78); // Широта
        send_uart_byte(8'h9A);
        send_uart_byte(8'hBC);
        send_uart_byte(8'hDE);
        send_uart_byte(8'hF0); // Долгота
        send_uart_byte(8'h12);
        send_uart_byte(8'h34);
        send_uart_byte(8'h56);
        send_uart_byte(8'h00); // Скорость (0.1 узлов)
        send_uart_byte(8'h64); // 10.0 узлов
        send_uart_byte(8'h00); // Курс (0.1 градусы)
        send_uart_byte(8'hB4); // 18.0 градусов
        send_uart_byte(8'h01); // Направление
        send_uart_byte(8'h68); // 360 градусов
        send_uart_byte(8'h00); // Статус навигации
        // Остальные байты (заполняем нулями)
        for (int i = 20; i < 32; i++) begin
            send_uart_byte(8'h00);
        end
        
        // Ждем завершения передачи
        wait(led_tx_active == 0);
        #10000;
        
        // Тест 2: Проверка обработки флагов HDLC
        $display("Тест 2: Проверка обработки флагов HDLC");
        
        // Отправляем сообщение, содержащее HDLC_FLAG (0x7E)
        send_uart_byte(8'h01); // Тип сообщения
        send_uart_byte(8'h7E); // Специальный байт (должен быть экранирован)
        send_uart_byte(8'h34);
        send_uart_byte(8'h56);
        // Остальные байты (заполняем)
        for (int i = 4; i < 32; i++) begin
            send_uart_byte(8'h00);
        end
        
        // Ждем завершения передачи
        wait(led_tx_active == 0);
        #10000;
        
        // Завершение симуляции
        $display("Тестирование завершено");
        $finish;
    end
    
    // Создание VCD файла
    initial begin
        $dumpfile("ais_transmitter_full.vcd");
        $dumpvars(0, ais_transmitter_full_tb);
    end
    
    // Мониторинг выхода AIS
    always @(ais_tx) begin
        $display("Время: %t, AIS_TX: %b", $time, ais_tx);
    end
    
    // Контроль времени выполнения
    initial begin
        #1000000;
        $display("Превышено время выполнения теста");
        $finish;
    end

endmodule