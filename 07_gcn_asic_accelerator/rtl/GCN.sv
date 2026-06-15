module GCN
#(
  parameter FEATURE_COLS = 96,
  parameter WEIGHT_ROWS = 96,
  parameter FEATURE_ROWS = 6,
  parameter WEIGHT_COLS = 3,
  parameter FEATURE_WIDTH = 5,
  parameter WEIGHT_WIDTH = 5,
  parameter DOT_PROD_WIDTH = 32,
  parameter ADDRESS_WIDTH = 13,
  parameter COUNTER_WEIGHT_WIDTH = $clog2(WEIGHT_COLS),
  parameter COUNTER_FEATURE_WIDTH = $clog2(FEATURE_ROWS),
  parameter MAX_ADDRESS_WIDTH = 2,
  parameter NUM_OF_NODES = 6,
  parameter COO_NUM_OF_COLS = 6,
  parameter COO_NUM_OF_ROWS = 2,
  parameter COO_BW = $clog2(COO_NUM_OF_COLS),
  parameter PAR = 32
)
(
  input  logic clk,
  input  logic reset,
  input  logic start,

  input  logic [WEIGHT_WIDTH-1:0] data_in [0:WEIGHT_ROWS-1],
  input  logic [2*COO_BW-1:0] coo_in,

  output logic [COO_BW-1:0] coo_address,
  output logic [ADDRESS_WIDTH-1:0] read_address,
  output logic enable_read,
  output logic done,
  output logic [MAX_ADDRESS_WIDTH-1:0] max_addi_answer [0:FEATURE_ROWS-1]
);

  localparam logic [ADDRESS_WIDTH-1:0] FEATURE_BASE_ADDR = 13'h200;

  typedef enum logic [3:0] {
    S_IDLE,
    S_LOAD_W_REQ,
    S_LOAD_W_CAP,
    S_LOAD_F_REQ,
    S_LOAD_F_CAP,
    S_MAC,
    S_AGG_INIT,
    S_AGG_REQ,
    S_AGG_CAP,
    S_ARGMAX,
    S_DONE
  } state_t;

  state_t state, next_state;

  logic [COUNTER_WEIGHT_WIDTH-1:0]  weight_idx;
  logic [COUNTER_FEATURE_WIDTH-1:0] feature_idx;
  logic [COO_BW-1:0] edge_idx;
  logic [COUNTER_FEATURE_WIDTH-1:0] argmax_idx;
  logic [$clog2(FEATURE_COLS):0] k_cnt;

  logic [WEIGHT_WIDTH-1:0] weight_store  [0:WEIGHT_COLS-1][0:WEIGHT_ROWS-1];
  logic [WEIGHT_WIDTH-1:0] feature_store [0:FEATURE_COLS-1];

  logic [DOT_PROD_WIDTH-1:0] fm_wm     [0:FEATURE_ROWS-1][0:WEIGHT_COLS-1];
  logic [DOT_PROD_WIDTH-1:0] adj_fm_wm [0:FEATURE_ROWS-1][0:WEIGHT_COLS-1];

  logic [DOT_PROD_WIDTH-1:0] mac_acc    [0:WEIGHT_COLS-1];
  logic [DOT_PROD_WIDTH-1:0] mac_part   [0:WEIGHT_COLS-1];

  logic [COO_BW-1:0] src_node_raw, dst_node_raw;
  logic [COO_BW-1:0] src_node, dst_node;

  assign src_node_raw = coo_in[2*COO_BW-1:COO_BW];
  assign dst_node_raw = coo_in[COO_BW-1:0];

  assign src_node = src_node_raw - 1'b1;
  assign dst_node = dst_node_raw - 1'b1;

  always_comb begin
    for (int c = 0; c < WEIGHT_COLS; c++) begin
      mac_part[c] = '0;
      for (int p = 0; p < PAR; p++) begin
        if ((k_cnt + p) < FEATURE_COLS) begin
          mac_part[c] += feature_store[k_cnt + p] * weight_store[c][k_cnt + p];
        end
      end
    end
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      state        <= S_IDLE;
      weight_idx   <= '0;
      feature_idx  <= '0;
      edge_idx     <= '0;
      argmax_idx   <= '0;
      k_cnt        <= '0;
      read_address <= '0;
      coo_address  <= '0;
      enable_read  <= 1'b0;
      done         <= 1'b0;

      for (int i = 0; i < WEIGHT_COLS; i++) begin
        mac_acc[i] <= '0;
      end

      for (int i = 0; i < FEATURE_ROWS; i++) begin
        max_addi_answer[i] <= '0;
        for (int j = 0; j < WEIGHT_COLS; j++) begin
          fm_wm[i][j]     <= '0;
          adj_fm_wm[i][j] <= '0;
        end
      end

      for (int i = 0; i < WEIGHT_COLS; i++) begin
        for (int j = 0; j < WEIGHT_ROWS; j++) begin
          weight_store[i][j] <= '0;
        end
      end

      for (int i = 0; i < FEATURE_COLS; i++) begin
        feature_store[i] <= '0;
      end
    end
    else begin
      case (state)

        S_IDLE: begin
          done        <= 1'b0;
          enable_read <= 1'b0;
          read_address <= '0;
          coo_address  <= '0;
          weight_idx   <= '0;
          feature_idx  <= '0;
          edge_idx     <= '0;
          argmax_idx   <= '0;
          k_cnt        <= '0;

          for (int i = 0; i < WEIGHT_COLS; i++) begin
            mac_acc[i] <= '0;
          end

          if (start) begin
            for (int r = 0; r < FEATURE_ROWS; r++) begin
              max_addi_answer[r] <= '0;
              for (int c = 0; c < WEIGHT_COLS; c++) begin
                fm_wm[r][c]     <= '0;
                adj_fm_wm[r][c] <= '0;
              end
            end
            state <= S_LOAD_W_REQ;
          end
        end

        S_LOAD_W_REQ: begin
          enable_read  <= 1'b1;
          read_address <= weight_idx;
          state        <= S_LOAD_W_CAP;
        end

        S_LOAD_W_CAP: begin
          enable_read <= 1'b0;

          for (int i = 0; i < WEIGHT_ROWS; i++) begin
            weight_store[weight_idx][i] <= data_in[i];
          end

          if (weight_idx == WEIGHT_COLS-1) begin
            weight_idx  <= '0;
            feature_idx <= '0;
            state       <= S_LOAD_F_REQ;
          end
          else begin
            weight_idx <= weight_idx + 1'b1;
            state      <= S_LOAD_W_REQ;
          end
        end

        S_LOAD_F_REQ: begin
          enable_read  <= 1'b1;
          read_address <= FEATURE_BASE_ADDR + feature_idx;
          state        <= S_LOAD_F_CAP;
        end

        S_LOAD_F_CAP: begin
          enable_read <= 1'b0;

          for (int i = 0; i < FEATURE_COLS; i++) begin
            feature_store[i] <= data_in[i];
          end

          k_cnt <= '0;
          for (int i = 0; i < WEIGHT_COLS; i++) begin
            mac_acc[i] <= '0;
          end

          state <= S_MAC;
        end

        S_MAC: begin
          if ((k_cnt + PAR) >= FEATURE_COLS) begin
            for (int c = 0; c < WEIGHT_COLS; c++) begin
              fm_wm[feature_idx][c] <= mac_acc[c] + mac_part[c];
              mac_acc[c] <= '0;
            end

            k_cnt <= '0;

            if (feature_idx == FEATURE_ROWS-1) begin
              feature_idx <= '0;
              state <= S_AGG_INIT;
            end
            else begin
              feature_idx <= feature_idx + 1'b1;
              state <= S_LOAD_F_REQ;
            end
          end
          else begin
            for (int c = 0; c < WEIGHT_COLS; c++) begin
              mac_acc[c] <= mac_acc[c] + mac_part[c];
            end

            k_cnt <= k_cnt + PAR;
            state <= S_MAC;
          end
        end

        S_AGG_INIT: begin
          for (int i = 0; i < FEATURE_ROWS; i++) begin
            for (int j = 0; j < WEIGHT_COLS; j++) begin
              adj_fm_wm[i][j] <= '0;
            end
          end

          edge_idx    <= '0;
          coo_address <= '0;
          state       <= S_AGG_REQ;
        end

        S_AGG_REQ: begin
          coo_address <= edge_idx;
          state       <= S_AGG_CAP;
        end

        S_AGG_CAP: begin
          for (int c = 0; c < WEIGHT_COLS; c++) begin
            adj_fm_wm[dst_node][c] <= adj_fm_wm[dst_node][c] + fm_wm[src_node][c];
            if (src_node != dst_node) begin
              adj_fm_wm[src_node][c] <= adj_fm_wm[src_node][c] + fm_wm[dst_node][c];
            end
          end

          if (edge_idx == COO_NUM_OF_COLS-1) begin
            argmax_idx <= '0;
            state <= S_ARGMAX;
          end
          else begin
            edge_idx <= edge_idx + 1'b1;
            state    <= S_AGG_REQ;
          end
        end

        S_ARGMAX: begin
          if ((adj_fm_wm[argmax_idx][0] >= adj_fm_wm[argmax_idx][1]) &&
              (adj_fm_wm[argmax_idx][0] >= adj_fm_wm[argmax_idx][2])) begin
            max_addi_answer[argmax_idx] <= 2'd0;
          end
          else if (adj_fm_wm[argmax_idx][1] >= adj_fm_wm[argmax_idx][2]) begin
            max_addi_answer[argmax_idx] <= 2'd1;
          end
          else begin
            max_addi_answer[argmax_idx] <= 2'd2;
          end

          if (argmax_idx == FEATURE_ROWS-1) begin
            state <= S_DONE;
          end
          else begin
            argmax_idx <= argmax_idx + 1'b1;
            state <= S_ARGMAX;
          end
        end

        S_DONE: begin
          done        <= 1'b1;
          enable_read <= 1'b0;
          state       <= S_DONE;
        end

        default: begin
          state <= S_IDLE;
        end
      endcase
    end
  end

endmodule
