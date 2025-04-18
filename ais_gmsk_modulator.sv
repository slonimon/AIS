// AIS GMSK Modulator (SystemVerilog adapted from slonimon/AIS)

module ais_gmsk_modulator #(
  parameter BIT_RATE          = 9600,        // bits/s
  parameter BT                = 0.4,           // Gaussian filter BT product
  parameter SAMPLES_PER_BIT = 16,           // Samples per bit
  parameter CORDIC_ENABLE   = 1,             // Enable CORDIC (1) or LUT (0)
  parameter CORDIC_ITERATIONS = 12,          // Number of CORDIC iterations (if CORDIC_ENABLE)
  parameter DATA_WIDTH        = 16,          // Output I/Q data width
  parameter ANGLE_WIDTH       = 32,          // Angle width (for CORDIC or LUT)
  parameter FILTER_LENGTH_BITS = 6,         // Filter length in bits
  parameter LUT_DEPTH         = 10           // LUT Depth for Sine/Cosine Generation
) (
  input  logic clk,                    // Clock signal
  input  logic rst,                    // Reset signal (active high)
  input  logic bit_in,                 // Input data bit
  input  logic bit_valid,              // Input bit valid signal
  output logic signed [DATA_WIDTH-1:0] i_out,  // I output
  output logic signed [DATA_WIDTH-1:0] q_out,  // Q output
  output logic                              valid_out   // Output valid signal
);

  // Internal parameters
  localparam FILTER_LENGTH = FILTER_LENGTH_BITS * SAMPLES_PER_BIT;

  // Internal signals
  logic signed [DATA_WIDTH-1:0] gaussian_filter_coeffs [FILTER_LENGTH-1:0];
  logic                             encoded_bit;
  logic                             prev_encoded_bit;
  logic signed [ANGLE_WIDTH-1:0] phase_accumulator;
  logic signed [ANGLE_WIDTH-1:0] phase_increment;
  logic signed [DATA_WIDTH-1:0] i_sample;
  logic signed [DATA_WIDTH-1:0] q_sample;

  // Gaussian Filter Module Instance
  gaussian_filter #(
    .BT(BT),
    .SAMPLES_PER_BIT(SAMPLES_PER_BIT),
    .DATA_WIDTH(DATA_WIDTH),
    .FILTER_LENGTH_BITS(FILTER_LENGTH_BITS)
  ) gaussian_filter_inst (
    .filter_coeffs(gaussian_filter_coeffs)
  );


  // Differential Encoding (adapted from slonimon/AIS)
  always_ff @(posedge clk) begin
    if (rst) begin
      prev_encoded_bit <= 1'b0;
      encoded_bit <= 1'b0;
    end else if (bit_valid) begin
      prev_encoded_bit <= encoded_bit;
      encoded_bit <= bit_in ^ prev_encoded_bit;  // XOR for differential encoding
    end
  end


  // Phase Accumulation
  always_ff @(posedge clk) begin
    if (rst) begin
      phase_accumulator <= 0;
      phase_increment <= 0;
    end else if (bit_valid) begin
      // Calculate phase increment based on encoded bit
      if (encoded_bit) begin
        phase_increment <= (1 << (ANGLE_WIDTH-1)) / SAMPLES_PER_BIT; // Scaled Pi / Samples Per Bit
      end else begin
        phase_increment <= -(1 << (ANGLE_WIDTH-1)) / SAMPLES_PER_BIT;
      end
    end
    phase_accumulator <= phase_accumulator + phase_increment;
  end


  // I/Q Generation (CORDIC or LUT)
  generate
    if (CORDIC_ENABLE) begin : cordic_iq
      // CORDIC Instance
      cordic_rotator #(
        .DATA_WIDTH(DATA_WIDTH),
        .ANGLE_WIDTH(ANGLE_WIDTH),
        .ITERATIONS(CORDIC_ITERATIONS)
      ) cordic_inst (
        .clk(clk),
        .rst(rst),
        .angle_in(phase_accumulator),
        .x_out(i_sample),  // Cosine
        .y_out(q_sample),  // Sine
        .valid_out()  // Assume CORDIC always valid for now; add logic if needed
      );
    end else begin : lut_iq

      // LUT-Based I/Q Generation
      logic signed [DATA_WIDTH-1:0] sine_table [(1<<LUT_DEPTH)-1:0];

      //Initialize the LUT
      initial begin
         for (int i = 0; i < (1<<LUT_DEPTH); i++) begin
            real angle = 2.0 * `PI * (real)i / (real)(1<<LUT_DEPTH);
            sine_table[i] = $sin(angle) * ((1 << (DATA_WIDTH - 1)) - 1); // Scale to DATA_WIDTH
         end
      end

      always_comb begin
          integer lut_index;
          lut_index = phase_accumulator[ANGLE_WIDTH-1 : ANGLE_WIDTH-LUT_DEPTH]; // Use top bits

          // Sine and cosine generation
          i_sample =  sine_table[(lut_index + (1<<(LUT_DEPTH-2))) % (1<<LUT_DEPTH)]; //cosine (Pi/2 phase shift)
          q_sample =  sine_table[lut_index]; //sine
      end
    end
  endgenerate


  // Output Logic
  always_ff @(posedge clk) begin
    if (rst) begin
      i_out <= 0;
      q_out <= 0;
      valid_out <= 0;
    end else if (bit_valid) begin
      i_out <= i_sample;
      q_out <= q_sample;
      valid_out <= 1;
    end else begin
      valid_out <= 0;
    end
  end

endmodule


// Gaussian Filter Module (Calculates Filter Coefficients)
module gaussian_filter #(
  parameter BT = 0.4,
  parameter SAMPLES_PER_BIT = 16,
  parameter DATA_WIDTH = 16,
  parameter FILTER_LENGTH_BITS = 6
) (
  output logic signed [DATA_WIDTH-1:0] filter_coeffs [((2 * FILTER_LENGTH_BITS) * SAMPLES_PER_BIT)-1:0]
);

  localparam FILTER_LENGTH = ((2 * FILTER_LENGTH_BITS) * SAMPLES_PER_BIT);
  real impulse_response [FILTER_LENGTH-1:0];
  real sum_of_squares;
  integer i;

  initial begin
    // Calculate Gaussian impulse response
    real T = 1.0 / (BIT_RATE);
    real sigma = sqrt(log(2.0) / (2.0 * `PI * BT * BT * T * T));
    real t;

    sum_of_squares = 0.0;

    for (i = 0; i < FILTER_LENGTH; i++) begin
      t = (real)(i - FILTER_LENGTH/2) / SAMPLES_PER_BIT * T;
      impulse_response[i] = (1.0 / (sigma * sqrt(2.0 * `PI))) * exp(-(t*t) / (2.0 * sigma*sigma));
      sum_of_squares = sum_of_squares + (impulse_response[i] * impulse_response[i]);
    end

    // Normalize and quantize
    for (i = 0; i < FILTER_LENGTH; i++) begin
      impulse_response[i] = impulse_response[i] / sqrt(sum_of_squares);
      filter_coeffs[i] = $signed(impulse_response[i] * ((1 << (DATA_WIDTH-2))-1)); //scale
    end
    $display("Gaussian filter coefficients initialized.");
  end
endmodule

// CORDIC Rotator Module (Vectoring Mode, for Sine/Cosine Generation)
module cordic_rotator #(
  parameter DATA_WIDTH = 16,    // Output data width
  parameter ANGLE_WIDTH = 32,   // Angle input width
  parameter ITERATIONS = 12     // Number of iterations
) (
  input  logic                            clk,
  input  logic                            rst,
  input  logic signed [ANGLE_WIDTH-1:0] angle_in,
  output logic signed [DATA_WIDTH-1:0] x_out,
  output logic signed [DATA_WIDTH-1:0] y_out,
  output logic                            valid_out
);

  // Internal signals
  logic signed [DATA_WIDTH+2:0] x_i [ITERATIONS:0];
  logic signed [DATA_WIDTH+2:0] y_i [ITERATIONS:0];
  logic signed [ANGLE_WIDTH:0] z_i [ITERATIONS:0];
  logic signed [ANGLE_WIDTH-1:0] arctan_lut [ITERATIONS-1:0];

  integer i;
  logic valid_internal;

  // Arctangent Look-Up Table (Shifted and Scaled)
  initial begin
      arctan_lut[0] = 32'd2056959758;  // atan(2^-0) * 2^(ANGLE_WIDTH-1) - EXAMPLE
      arctan_lut[1] = 32'd1290835561;  // atan(2^-1) * 2^(ANGLE_WIDTH-1) - EXAMPLE
      arctan_lut[2] = 32'd775446977;   // atan(2^-2) * 2^(ANGLE_WIDTH-1) - EXAMPLE
      arctan_lut[3] = 32'd406173192;
      arctan_lut[4] = 32'd203453764;
      arctan_lut[5] = 32'd101742131;
      arctan_lut[6] = 32'd50872281;
      arctan_lut[7] = 32'd25436242;
      arctan_lut[8] = 32'd12718131;
      arctan_lut[9] = 32'd6359067;
      arctan_lut[10] = 32'd3179534;
      arctan_lut[11] = 32'd1589767;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      x_i[0] <= {DATA_WIDTH+3{1'b0}};
      y_i[0] <= {DATA_WIDTH+3{1'b0}};
      x_i[0][DATA_WIDTH+2] <= 1'b0;
      z_i[0] <= angle_in;
      valid_internal <= 1'b0;
    end else begin
      for (i = 0; i < ITERATIONS; i++) begin
        if (i == 0) begin
          x_i[i+1] <= x_i[i] - ($signed(y_i[i]) >>> i) ;
          y_i[i+1] <= y_i[i] + ($signed(x_i[i]) >>> i) ;
          if (z_i[i] >= 0)
            z_i[i+1] <= z_i[i] - arctan_lut[i];
          else
            z_i[i+1] <= z_i[i] + arctan_lut[i];
        end else begin
          x_i[i+1] <= x_i[i] - ($signed(y_i[i]) >>> i) ;
          y_i[i+1] <= y_i[i] + ($signed(x_i[i]) >>> i) ;
          if (z_i[i] >= 0)
            z_i[i+1] <= z_i[i] - arctan_lut[i];
          else
            z_i[i+1] <= z_i[i] + arctan_lut[i];
        end
      end
      valid_internal <= 1'b1;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      x_out <= 0;
      y_out <= 0;
      valid_out <= 0;
    end else begin
        if (valid_internal) begin
            x_out <= x_i[ITERATIONS][DATA_WIDTH+1:2];
            y_out <= y_i[ITERATIONS][DATA_WIDTH+1:2];
            valid_out <= 1'b1;
        end else begin
            valid_out <= 1'b0;
        end
    end
  end
endmodule