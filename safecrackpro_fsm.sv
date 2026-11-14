module safecrackpro_fsm (
    input  logic            clk,
    input  logic            rstn,
    input  logic [2:0]      btn,                  // bit 0: confirmar | bit 1: inc | bit 2: dec
    output logic [3:0][3:0] digits,               // 4 dígitos BCD de 4 bits cada
    output logic [1:0]      current_position_idx, // índice da posição ativa (0 a 3)
    output logic [17:0]     led_red,              // 18 LEDs vermelhos (senha errada)
    output logic [8:0]      led_green             // 9 LEDs verdes (senha correta)
);

	// =======================================================================
	// 1. Detector de borda dos botões (ativo-baixo -> pulso de 1 clock)

	logic [2:0] btn_pos;  // Botões convertidos para ativo-alto ('1' = pressionado)
	logic [2:0] btn_prev; // Estado dos botões no ciclo de clock anterior
	logic [2:0] btn_edge; // Pulso de 1 ciclo quando ocorre transição 0 -> 1

	always_comb begin
		 btn_pos  = ~btn;
		 btn_edge = btn_pos & ~btn_prev;
	end

	always_ff @(posedge clk or negedge rstn) begin
		 if (~rstn) begin
			  btn_prev <= 3'b000;
		 end else begin
			  btn_prev <= btn_pos;
		 end
	end

	// =======================================================================
	// 2. Definição dos estados da FSM, senha e temporizador

	typedef enum logic [2:0] {
		 START               = 3'd0, // Estado inicial / reset dos dígitos
		 CURRENT_POSITION    = 3'd1, // Edição do dígito ativo (0 a 3)
		 CHECK_PASSWORD      = 3'd2, // Compara os 4 dígitos com a senha
		 WAIT_GREEN_LED_TIME = 3'd3, // Senha correta: LEDs verdes por 5s
		 WAIT_RED_LED_TIME   = 3'd4  // Senha incorreta: LEDs vermelhos por 3s
	} state_t;

	state_t state, next_state;

	// Constantes de tempo para o clock de 50 MHz da placa DE2-115
	localparam int TIME_5S = 250_000_000; // 5 segundos
	localparam int TIME_3S = 150_000_000; // 3 segundos

	// Senha correta esperada pelo testbench: 1-2-3-4 (digits[0..3])
	localparam logic [3:0] PWD_0 = 4'd1;
	localparam logic [3:0] PWD_1 = 4'd2;
	localparam logic [3:0] PWD_2 = 4'd3;
	localparam logic [3:0] PWD_3 = 4'd4;

	// Contador de tempo dos LEDs (nome obrigatório para o testbench)
	logic [$clog2(TIME_5S)-1:0] led_time_cnt, next_led_time_cnt;

	// Próximos valores para os registradores de saída
	logic [3:0][3:0] next_digits;
	logic [1:0]      next_position_idx;

	// =======================================================================
	// 3. Lógica sequencial (registradores da FSM, dígitos e timer)

	always_ff @(posedge clk or negedge rstn) begin
		 if (~rstn) begin
			  state                <= START;
			  digits               <= '0;
			  current_position_idx <= 2'b00;
			  led_time_cnt         <= '0;
		 end else begin
			  state                <= next_state;
			  digits               <= next_digits;
			  current_position_idx <= next_position_idx;
			  led_time_cnt         <= next_led_time_cnt;
		 end
	end

	// =======================================================================
	// 4. Lógica combinacional (próximo estado, datapath e wrap-around)

	always_comb begin
		 // Valores padrão para evitar Inferred Latches
		 next_state        = state;
		 next_digits       = digits;
		 next_position_idx = current_position_idx;
		 next_led_time_cnt = led_time_cnt;

		 unique case (state)
			  START: begin
					next_digits       = '0;
					next_position_idx = 2'b00;
					next_led_time_cnt = '0;
					next_state        = CURRENT_POSITION;
			  end

			  CURRENT_POSITION: begin
					if (btn_edge[1]) begin // INC_DIGIT (KEY2): incrementa dígito ativo com wrap-around 9 -> 0
						 if (digits[current_position_idx] == 4'd9)
							  next_digits[current_position_idx] = 4'd0;
						 else
							  next_digits[current_position_idx] = digits[current_position_idx] + 4'd1;
					end else if (btn_edge[2]) begin // DEC_DIGIT (KEY3): decrementa dígito ativo com wrap-around 0 -> 9
						 if (digits[current_position_idx] == 4'd0)
							  next_digits[current_position_idx] = 4'd9;
						 else
							  next_digits[current_position_idx] = digits[current_position_idx] - 4'd1;
					end else if (btn_edge[0]) begin // INC_POSITION (KEY1): avança posição ou dispara verificação no 4º dígito
						 if (current_position_idx < 2'd3)
							  next_position_idx = current_position_idx + 2'd1;
						 else
							  next_state = CHECK_PASSWORD;
					end
			  end

			  CHECK_PASSWORD: begin
					if (digits[0] == PWD_0 && digits[1] == PWD_1 && digits[2] == PWD_2 && digits[3] == PWD_3) begin
						 next_state        = WAIT_GREEN_LED_TIME;
						 next_led_time_cnt = TIME_5S;
					end else begin
						 next_state        = WAIT_RED_LED_TIME;
						 next_led_time_cnt = TIME_3S;
					end
			  end

			  WAIT_GREEN_LED_TIME: begin
					if (led_time_cnt > 0) begin
						 next_led_time_cnt = led_time_cnt - 1;
					end else begin
						 next_digits       = '0;
						 next_position_idx = 2'b00;
						 next_state        = START;
					end
			  end

			  WAIT_RED_LED_TIME: begin
					if (led_time_cnt > 0) begin
						 next_led_time_cnt = led_time_cnt - 1;
					end else begin
						 next_digits       = '0;
						 next_position_idx = 2'b00;
						 next_state        = START;
					end
			  end

        default: next_state = START;
    endcase
end

	// =======================================================================
	// 5. Lógica combinacional de saída dos LEDs

	always_comb begin
		 led_green = (state == WAIT_GREEN_LED_TIME) ? 9'h1FF   : 9'h000;
		 led_red   = (state == WAIT_RED_LED_TIME)   ? 18'h3FFFF : 18'h00000;
	end

endmodule