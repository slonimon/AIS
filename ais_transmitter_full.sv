module ais_transmitter_full (
    input  wire        clk,          // 50 MHz
    input  wire        reset_n,
    input  wire        uart_rx,      // 38400 бод, сырые данные
    output reg         ais_tx,       // HDLC кодированный выход
    output reg         led_ready,
    output reg         led_tx_active
);

    // Параметры протокола
    parameter HDLC_FLAG = 8'h7E;
    parameter HDLC_ESC = 8'h7D;
    parameter NMEA_MAX_LEN = 82;
    parameter BIT_STUFF_THRESHOLD = 5;
    
    // Состояния автомата
    parameter [2:0] 
        IDLE         = 3'd0,
        RECEIVE_DATA = 3'd1,
        BUILD_NMEA   = 3'd2,
        CALC_CRC     = 3'd3,
        HDLC_START_FLAG = 3'd4,
        HDLC_SEND    = 3'd5,
        HDLC_END_FLAG = 3'd6;
    
    reg [2:0] state;

    // Буферы данных
    reg [7:0] raw_data_buffer [0:255];
    reg [7:0] nmea_buffer [0:NMEA_MAX_LEN-1];
    reg [7:0] tx_byte;
    
    // Индексы и счетчики
    reg [7:0] raw_data_index;
    reg [6:0] nmea_index;
    reg [6:0] nmea_length;
    reg [3:0] bit_counter;
    reg [3:0] ones_counter;
    
    // UART интерфейс
    wire [7:0] uart_data;
    wire uart_valid;
    wire uart_error;
    
    // Контроль передачи
    reg tx_start;
    reg tx_busy;
    reg crc_enable;
    reg [15:0] crc;
    reg crc_ready;
    
    // Данные AIS (замена структуры)
    reg [7:0]  msg_type;
    reg [31:0] mmsi;
    reg [31:0] latitude;
    reg [31:0] longitude;
    reg [15:0] speed;
    reg [15:0] course;
    reg [15:0] heading;
    reg [7:0]  nav_status;

    // Instantiate UART Receiver
    uart_receiver #(
        .CLK_FREQ(50_000_000),
        .BAUD_RATE(38_400)
    ) uart_rx_inst (
        .clk(clk),
        .reset_n(reset_n),
        .rx(uart_rx),
        .data(uart_data),
        .valid(uart_valid),
        .error(uart_error)
    );

    // Функция преобразования 4-бит в HEX символ
    function [7:0] hex_char;
        input [3:0] val;
        begin
            hex_char = (val > 9) ? (val + 55) : (val + 48);
        end
    endfunction

    // Парсинг сырых данных
    task parse_raw_data;
    begin
        msg_type = raw_data_buffer[0];
        mmsi = {raw_data_buffer[1], raw_data_buffer[2], raw_data_buffer[3], 8'h00};
        latitude = {raw_data_buffer[4], raw_data_buffer[5], raw_data_buffer[6], raw_data_buffer[7]};
        longitude = {raw_data_buffer[8], raw_data_buffer[9], raw_data_buffer[10], raw_data_buffer[11]};
        speed = {raw_data_buffer[12], raw_data_buffer[13]};
        course = {raw_data_buffer[14], raw_data_buffer[15]};
        heading = {raw_data_buffer[16], raw_data_buffer[17]};
        nav_status = raw_data_buffer[18];
    end
    endtask

    // Добавление координат в NMEA сообщение
    task add_coordinate;
        input [31:0] coord;
        input [7:0] pos_char;
        input [7:0] neg_char;
        reg [31:0] abs_coord;
        reg [7:0] hemisphere;
        reg [31:0] degrees;
        reg [31:0] minutes;
    begin
        abs_coord = coord[31] ? -coord : coord;
        hemisphere = coord[31] ? neg_char : pos_char;
        degrees = abs_coord / 100000;
        minutes = (abs_coord % 100000) * 60 / 100000;
        
        nmea_buffer[nmea_index] <= ",";
        nmea_index <= nmea_index + 1;
        
        // Градусы (DD)
        if (degrees < 10) begin
            nmea_buffer[nmea_index] <= "0";
            nmea_buffer[nmea_index+1] <= "0" + degrees[3:0];
            nmea_index <= nmea_index + 2;
        end else begin
            nmea_buffer[nmea_index] <= "0" + (degrees / 10);
            nmea_buffer[nmea_index+1] <= "0" + (degrees % 10);
            nmea_index <= nmea_index + 2;
        end
        
        // Минуты (MM.MMMMM)
        nmea_buffer[nmea_index] <= "0" + (minutes / 10);
        nmea_buffer[nmea_index+1] <= "0" + (minutes % 10);
        nmea_buffer[nmea_index+2] <= ".";
        nmea_index <= nmea_index + 3;
        
        // Дробная часть минут
        begin
            integer i;
            reg [31:0] frac;
            frac = (minutes % 1) * 100000;
            for (i = 10000; i >= 1; i = i / 10) begin
                nmea_buffer[nmea_index] <= "0" + ((frac / i) % 10);
                nmea_index <= nmea_index + 1;
            end
        end
        
        // Полушарие
        nmea_buffer[nmea_index] <= ",";
        nmea_buffer[nmea_index+1] <= hemisphere;
        nmea_index <= nmea_index + 2;
    end
    endtask

    // Формирование NMEA сообщения
    task build_nmea_message;
    begin
        // Поле 6: Данные сообщения
        // Добавляем MMSI (9 цифр)
        begin
            integer i;
            for (i = 8; i >= 0; i = i - 1) begin
                nmea_buffer[nmea_index] <= "0" + ((mmsi >> (4*i)) & 4'hF);
                nmea_index <= nmea_index + 1;
            end
        end
        
        // Добавляем статус навигации
        nmea_buffer[nmea_index] <= ",";
        nmea_buffer[nmea_index+1] <= "0" + nav_status[3:0];
        nmea_index <= nmea_index + 2;
        
        // Добавляем скорость (формат: SSS.S)
        nmea_buffer[nmea_index] <= ",";
        nmea_buffer[nmea_index+1] <= "0" + (speed / 1000);
        nmea_buffer[nmea_index+2] <= "0" + ((speed % 1000) / 100);
        nmea_buffer[nmea_index+3] <= ".";
        nmea_buffer[nmea_index+4] <= "0" + ((speed % 100) / 10);
        nmea_index <= nmea_index + 5;
        
        // Добавляем курс (формат: CCC.C)
        nmea_buffer[nmea_index] <= ",";
        nmea_buffer[nmea_index+1] <= "0" + (course / 1000);
        nmea_buffer[nmea_index+2] <= "0" + ((course % 1000) / 100);
        nmea_buffer[nmea_index+3] <= ".";
        nmea_buffer[nmea_index+4] <= "0" + ((course % 100) / 10);
        nmea_index <= nmea_index + 5;
        
        // Добавляем координаты
        add_coordinate(latitude, "N", "S");
        add_coordinate(longitude, "E", "W");
    end
    endtask

    // Основной автомат обработки
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= IDLE;
            raw_data_index <= 0;
            nmea_index <= 0;
            led_ready <= 0;
            led_tx_active <= 0;
            crc_enable <= 0;
            msg_type <= 0;
            mmsi <= 0;
            latitude <= 0;
            longitude <= 0;
            speed <= 0;
            course <= 0;
            heading <= 0;
            nav_status <= 0;
        end else begin
            case (state)
                IDLE: begin
                    led_ready <= 1;
                    if (uart_valid) begin
                        raw_data_buffer[raw_data_index] <= uart_data;
                        raw_data_index <= raw_data_index + 1;
                        state <= RECEIVE_DATA;
                    end
                end
                
                RECEIVE_DATA: begin
                    if (uart_valid) begin
                        raw_data_buffer[raw_data_index] <= uart_data;
                        if (raw_data_index == 8'h1F) begin // Пример: 32 байта данных
                            parse_raw_data();
                            state <= BUILD_NMEA;
                        end else begin
                            raw_data_index <= raw_data_index + 1;
                        end
                    end
                end
                
                BUILD_NMEA: begin
                    // Формируем NMEA сообщение
                    nmea_buffer[0] <= "$";  // Начало NMEA
                    nmea_buffer[1] <= "A";  // AIVDM
                    nmea_buffer[2] <= "I";
                    nmea_buffer[3] <= "V";
                    nmea_buffer[4] <= "D";
                    nmea_buffer[5] <= "M";
                    nmea_buffer[6] <= ","; // Поле 1
                    nmea_buffer[7] <= "1"; // Поле 2
                    nmea_buffer[8] <= ",";
                    nmea_buffer[9] <= "1"; // Поле 3
                    nmea_buffer[10] <= ",";
                    nmea_buffer[11] <= "A"; // Поле 4
                    nmea_buffer[12] <= ",";
                    nmea_buffer[13] <= "A"; // Поле 5
                    nmea_buffer[14] <= ",";
                    
                    nmea_index <= 15;
                    build_nmea_message();
                    
                    state <= CALC_CRC;
                end
                
                CALC_CRC: begin
                    // Вычисляем CRC для NMEA сообщения (без $ и *)
                    crc_enable <= 1;
                    if (crc_ready) begin
                        // Добавляем * и CRC
                        nmea_buffer[nmea_index] <= "*";
                        nmea_buffer[nmea_index+1] <= hex_char(crc[15:12]);
                        nmea_buffer[nmea_index+2] <= hex_char(crc[11:8]);
                        nmea_buffer[nmea_index+3] <= hex_char(crc[7:4]);
                        nmea_buffer[nmea_index+4] <= hex_char(crc[3:0]);
                        nmea_buffer[nmea_index+5] <= 8'h0D; // CR
                        nmea_buffer[nmea_index+6] <= 8'h0A; // LF
                        nmea_length <= nmea_index + 7;
                        state <= HDLC_START_FLAG;
                    end
                end
                
                HDLC_START_FLAG: begin
                    tx_byte <= HDLC_FLAG;
                    tx_start <= 1;
                    nmea_index <= 0;
                    state <= HDLC_SEND;
                    led_tx_active <= 1;
                    crc_enable <= 0;
                end
                
                HDLC_SEND: begin
                    if (tx_start) begin
                        tx_start <= 0;
                    end else if (!tx_busy) begin
                        if (nmea_index < nmea_length) begin
                            // HDLC escaping
                            if ((nmea_buffer[nmea_index] == HDLC_FLAG) || 
                                (nmea_buffer[nmea_index] == HDLC_ESC)) begin
                                tx_byte <= HDLC_ESC;
                                // Следующим байтом будет оригинальный XOR 0x20
                            end else begin
                                tx_byte <= nmea_buffer[nmea_index];
                                nmea_index <= nmea_index + 1;
                            end
                            tx_start <= 1;
                        end else begin
                            state <= HDLC_END_FLAG;
                        end
                    end
                end
                
                HDLC_END_FLAG: begin
                    tx_byte <= HDLC_FLAG;
                    tx_start <= 1;
                    state <= IDLE;
                    led_tx_active <= 0;
                    raw_data_index <= 0;
                end
            endcase
        end
    end

    // Модуль расчета CRC-16-CCITT
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            crc <= 16'hFFFF;
            crc_ready <= 0;
        end else begin
            if (state == BUILD_NMEA) begin
                crc <= 16'hFFFF;
                crc_ready <= 0;
            end else if (crc_enable) begin
                if (nmea_index < nmea_length - 5) begin // Исключаем *CRC<CR><LF>
                    begin
                        integer i;
                        reg crc_msb;
                        for (i = 0; i < 8; i = i + 1) begin
                            crc_msb = crc[15];
                            crc[15] = crc[14];
                            crc[14] = crc[13];
                            crc[13] = crc[12];
                            crc[12] = crc[11] ^ crc_msb;
                            crc[11] = crc[10];
                            crc[10] = crc[9];
                            crc[9] = crc[8];
                            crc[8] = crc[7] ^ crc_msb;
                            crc[7] = crc[6];
                            crc[6] = crc[5];
                            crc[5] = crc[4] ^ crc_msb;
                            crc[4] = crc[3];
                            crc[3] = crc[2];
                            crc[2] = crc[1];
                            crc[1] = crc[0];
                            crc[0] = crc_msb;
                            
                            if (nmea_buffer[nmea_index][i] ^ crc_msb) begin
                                crc <= crc ^ 16'h1021;
                            end
                        end
                    end
                    nmea_index <= nmea_index + 1;
                end else begin
                    crc_ready <= 1;
                end
            end
        end
    end

    // Последовательный передатчик с битовым стаффингом
    always @(posedge clk) begin
        if (tx_start) begin
            bit_counter <= 0;
            ones_counter <= 0;
            ais_tx <= 0; // Стартовый бит
            tx_busy <= 1;
        end else if (tx_busy) begin
            if (bit_counter < 8) begin
                ais_tx <= tx_byte[bit_counter];
                if (tx_byte[bit_counter]) begin
                    ones_counter <= ones_counter + 1;
                    if (ones_counter == BIT_STUFF_THRESHOLD) begin
                        // Вставляем 0 после 5 единиц
                        ais_tx <= 0;
                        ones_counter <= 0;
                        // bit_counter не увеличиваем (повторяем текущий бит)
                    end
                end else begin
                    ones_counter <= 0;
                end
                bit_counter <= bit_counter + 1;
            end else begin
                ais_tx <= 1; // Стоповый бит
                tx_busy <= 0;
            end
        end
    end

endmodule