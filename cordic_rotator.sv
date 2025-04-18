// CORDIC Rotator Module (Vectoring Mode, for Sine/Cosine Generation)
module cordic_rotator #(
  parameter DATA_WIDTH = 16,     // Output data width
  parameter ANGLE_WIDTH = 32,    // Angle input width
  parameter ITERATIONS = 12      // Number of iterations (determines accuracy)
) (
  input clk,
  input rst,
  input signed [ANGLE_WIDTH-1:0] angle_in, // Angle in radians (scaled)
  output logic signed [DATA_WIDTH-1:0] x_out,
  output logic signed [DATA_WIDTH-1:0] y_out,
  output logic valid_out
);

  // Internal signals
  logic signed [DATA_WIDTH+2:0] x_i [ITERATIONS:0]; // Expanded precision to prevent overflow
  logic signed [DATA_WIDTH+2:0] y_i [ITERATIONS:0];
  logic signed [ANGLE_WIDTH:0] z_i [ITERATIONS:0];

  logic signed [ANGLE_WIDTH-1:0] arctan_lut [ITERATIONS-1:0]; // Precomputed arctan values

  integer i;
  logic valid_internal;


  // Arctangent Look-Up Table (Shifted and Scaled)
  //  These values must be calculated and pre-loaded!
  //  Use Python (numpy.arctan and proper scaling)
  initial begin
      arctan_lut[0] = 32'd2056959758;  // atan(2^-0) * 2^(ANGLE_WIDTH-1) - EXAMPLE, CHANGE!
      arctan_lut[1] = 32'd1290835561;  // atan(2^-1) * 2^(ANGLE_WIDTH-1) - EXAMPLE, CHANGE!
      arctan_lut[2] = 32'd775446977;   // atan(2^-2) * 2^(ANGLE_WIDTH-1) - EXAMPLE, CHANGE!
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


  // Iterative CORDIC Algorithm
  always_ff @(posedge clk) begin
    if (rst) begin
      x_i[0] <= {DATA_WIDTH+3{1'b0}}; // Initialize X (scaled to avoid overflow)
      y_i[0] <= {DATA_WIDTH+3{1'b0}}; // Initialize Y
      x_i[0][DATA_WIDTH+2] <= 1'b0;  // Set to positive for scaling
      z_i[0] <= angle_in;          // Initialize Z (angle accumulator)
      valid_internal <= 1'b0;
    end else begin
      for (i = 0; i < ITERATIONS; i++) begin
        if (i == 0) begin
          x_i[i+1] <= x_i[i] - ($signed(y_i[i]) >>> i) ; // Avoid divide by power of 2 for FPGA
          y_i[i+1] <= y_i[i] + ($signed(x_i[i]) >>> i) ;
          if (z_i[i] >= 0)
            z_i[i+1] <= z_i[i] - arctan_lut[i];
          else
            z_i[i+1] <= z_i[i] + arctan_lut[i];
        end else begin
          x_i[i+1] <= x_i[i] - ($signed(y_i[i]) >>> i) ; // Avoid divide by power of 2 for FPGA
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


  // Output Assignment and Scaling
  always_ff @(posedge clk) begin
    if (rst) begin
      x_out <= 0;
      y_out <= 0;
      valid_out <= 0;
    end else begin
        if (valid_internal) begin
            x_out <= x_i[ITERATIONS][DATA_WIDTH+1:2];   // Drop extra bits from expanded prescision
            y_out <= y_i[ITERATIONS][DATA_WIDTH+1:2];   // Output scaled results.
            valid_out <= 1'b1;
        end else begin
            valid_out <= 1'b0;
        end
    end
  end

endmodule