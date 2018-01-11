library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity partitioner3 is
generic(
	PEND_THRESH : integer := 1;
	ADDR_LMT : integer := 20;
	MDATA : integer := 14;
	MAX_RADIX_BITS : integer := 13);
port(
	Clk_32UI : in std_logic;
	Resetb : in std_logic;

	l12ab_WrAddr : 		out std_logic_vector(ADDR_LMT-1 downto 0);	--write address
	l12ab_WrTID :		out std_logic_vector(13 downto 0);			--meta data
	l12ab_WrDin :		out std_logic_vector(511 downto 0);			--cache line data
	l12ab_WrEn :		out std_logic;								--write enable
	ab2l1_WrSent :		in std_logic;								--write issued
	ab2l1_WrAlmFull :	in std_logic;								--write fifo almost full

	l12ab_RdAddr :		out std_logic_vector(ADDR_LMT-1 downto 0);	--reads may yield to writes
	l12ab_RdTID :		out std_logic_vector(13 downto 0);			--meta data
	l12ab_RdEn :		out std_logic;								--read enable
	ab2l1_RdSent :		in std_logic;								--read issued

	ab2l1_RdRspValid :	in std_logic;								--read response valid
	ab2l1_CfgValid : 	in std_logic;
	ab2l1_RdRsp :		in std_logic_vector(13 downto 0);			--read response header
	ab2l1_RdRspAddr : 	in std_logic_vector(ADDR_LMT-1 downto 0);	--read response address
	ab2l1_RdData :		in std_logic_vector(511 downto 0);			--read data
	ab2l1_stallRd :		in std_logic;								--stall read requests FOR LPBK1

	ab2l1_WrRspValid :	in std_logic;								--write response valid
	ab2l1_WrRsp :		in std_logic_vector(13 downto 0);			--write response header
	ab2l1_WrRspAddr :	in std_logic_vector(ADDR_LMT-1 downto 0);	--write response address

	re2xy_go : 			in std_logic;								--start the test
	re2xy_src_addr : 	in std_logic_vector(31 downto 0);
	re2xy_dst_addr : 	in std_logic_vector(31 downto 0);
	re2xy_NumLines :	in std_logic_vector(31 downto 0);			--number of cache lines
	re2xy_expected_NumLines :	in std_logic_vector(31 downto 0);
	re2xy_addr_reset : 		in std_logic_vector(31 downto 0);
	re2xy_read_offset : 	in std_logic_vector(31 downto 0);
	re2xy_write_offset : 	in std_logic_vector(31 downto 0);
	re2xy_dummy_key :		in std_logic_vector(31 downto 0);
	re2xy_radix_bits :		in std_logic_vector(31 downto 0);
	re2xy_Cont :		in std_logic;								--continuous mode
	re2xy_test_cfg : in std_logic_vector(7 downto 0);

	read_NumLines : 	in std_logic_vector(31 downto 0);
	reset_read_NumLines : out std_logic;
	decomp_almostfull : in std_logic;
	decomp_fifos_free_count : in std_logic_vector(31 downto 0);
	decomp_stop_sending : out std_logic;
	l12ab_TestCmp : 	out std_logic;								--test completion flag
	l12ab_ErrorInfo :	out std_logic_vector(255 downto 0);			--error information
	l12ab_ErrorValid :	out std_logic;								--test has detected an error

	test_Resetb : 		in std_logic);
end partitioner3;

architecture behavioral of partitioner3 is

constant PAGE_SIZE_IN_BITS : integer := 16;
--constant PAGE_SIZE_IN_BITS : integer := 7;
constant PAGE_SIZE : integer := 2**PAGE_SIZE_IN_BITS;
constant ONE : unsigned(13 downto 0) := "00000000000001";
constant MAX_FANOUT : integer := 2**MAX_RADIX_BITS;
constant FIFO_DEPTH_BITS : integer := 8;

signal FANOUT : integer;
signal PARTITION_SIZE : unsigned(31 downto 0) := (others => '0');
signal PARTITION_SIZE_WITH_PADDING : unsigned(31 downto 0) := (others => '0');
signal PADDING_SIZE_DIVIDER : integer range 0 to 15 := 0;
signal MASK : std_logic_vector(MAX_RADIX_BITS-1 downto 0);

signal src_bram_we : std_logic;
signal src_bram_re : std_logic;
signal src_bram_re_1d : std_logic;
signal src_bram_raddr : std_logic_vector(10 downto 0);
signal src_bram_raddr_1d : std_logic_vector(10 downto 0);
signal src_bram_waddr : std_logic_vector(10 downto 0);
signal src_bram_din : std_logic_vector(ADDR_LMT-1 downto 0);
signal src_bram_dout : std_logic_vector(ADDR_LMT-1 downto 0);
signal src_bram_waddr_count : unsigned(10 downto 0);

signal dst_bram_we : std_logic;
signal dst_bram_re : std_logic;
signal dst_bram_re_1d : std_logic;
signal dst_bram_raddr : std_logic_vector(10 downto 0);
signal dst_bram_waddr : std_logic_vector(10 downto 0);
signal dst_bram_din : std_logic_vector(ADDR_LMT-1 downto 0);
signal dst_bram_dout : std_logic_vector(ADDR_LMT-1 downto 0);
signal dst_bram_waddr_count : unsigned(10 downto 0);

signal RdSent_was_down : std_logic;
signal RdSent_was_down_1d : std_logic;
signal current_RdAddr : std_logic_vector(ADDR_LMT-1 downto 0);
signal current_RdAddr_1d : std_logic_vector(ADDR_LMT-1 downto 0);
signal current_RdAddr_2d : std_logic_vector(ADDR_LMT-1 downto 0);
signal current_WrAddr : std_logic_vector(ADDR_LMT-1 downto 0);
signal current_WrAddr_1d : std_logic_vector(ADDR_LMT-1 downto 0);
signal current_WrDin : std_logic_vector(511 downto 0);
signal current_WrDin_1d : std_logic_vector(511 downto 0);

signal j : integer := 0;
signal i : integer := 0;
signal i_1d : integer := 0;
signal i_2d : integer := 0;
signal i_3d : integer := 0;
signal i_4d : integer := 0;

signal NumberOfCacheLinesToRead : unsigned(ADDR_LMT-1 downto 0) := (others => '0');
signal NumberOfReadCacheLines : unsigned(ADDR_LMT-1 downto 0) := (others => '0');
signal NumberOfExpectedCacheLines : unsigned(ADDR_LMT-1 downto 0) := (others => '0');
signal NumberOfRequestedLines : unsigned(ADDR_LMT-1 downto 0) := (others => '0');
signal NumberOfRequestedLines_1d : unsigned(ADDR_LMT-1 downto 0) := (others => '0');
signal NumberOfRequestedLines_2d : unsigned(ADDR_LMT-1 downto 0) := (others => '0');
signal NumberOfReceivedLines : unsigned(ADDR_LMT-1 downto 0) := (others => '0');
signal NumberOfSentLines : unsigned(ADDR_LMT-1 downto 0) := (others => '0');
signal NumberOfCompletedWrites : unsigned(ADDR_LMT-1 downto 0) := (others => '0');

signal request_issued : std_logic := '0';
signal send_issued : std_logic := '0';
signal send_pending : std_logic := '0';

type hash_data_type is array (7 downto 0) of std_logic_vector(MAX_RADIX_BITS + 63 downto 0);

signal hash_request : std_logic;
signal cl_of_keys : std_logic_vector(511 downto 0);
signal hash_out_valid : std_logic_vector(7 downto 0);
signal hash_out_data : hash_data_type;

type fifo_data_type is array (7 downto 0) of std_logic_vector(MAX_RADIX_BITS + 63 downto 0);
type fifo_count_type is array (7 downto 0) of std_logic_vector(FIFO_DEPTH_BITS-1 downto 0);

signal fifo_re : std_logic_vector(7 downto 0);
signal fifo_valid : std_logic_vector(7 downto 0);
signal fifo_din : fifo_data_type;
signal fifo_dout : fifo_data_type;
signal fifo_count :	fifo_count_type;
signal fifo_empty : std_logic_vector(7 downto 0);
signal fifo_full : std_logic_vector(7 downto 0);
signal fifo_almostfull: std_logic_vector(7 downto 0);
signal fifos_almostfull : std_logic;
signal fifos_count : std_logic_vector(FIFO_DEPTH_BITS-1 downto 0) := (others => '0');
signal fifos_free_count : integer range 0 to 2**FIFO_DEPTH_BITS-1;

type dfifo_data_type is array (7 downto 0) of std_logic_vector(4 + MAX_RADIX_BITS + 511 downto 0);

signal dfifo_re : std_logic_vector(7 downto 0);
signal dfifo_valid : std_logic_vector(7 downto 0);
signal dfifo_dout : dfifo_data_type;
signal dfifo_empty : std_logic_vector(7 downto 0);
signal dfifo_almostfull : std_logic_vector(7 downto 0);
signal dfifos_empty : std_logic;
signal dfifos_empty_d : std_logic_vector(15 downto 0);
signal dfifos_empty_end : std_logic;
signal dfifos_almostfull : std_logic;

signal aw_bram_we : std_logic;
signal aw_bram_re : std_logic;
signal aw_bram_raddr : std_logic_vector(MAX_RADIX_BITS-1 downto 0);
signal aw_bram_waddr : std_logic_vector(MAX_RADIX_BITS-1 downto 0);
signal aw_bram_din : std_logic_vector(15 downto 0);
signal aw_bram_dout : std_logic_vector(15 downto 0);

signal aw_bram_re_1d : std_logic;
signal aw_bram_raddr_1d : std_logic_vector(MAX_RADIX_BITS-1 downto 0);
signal aw_bram_waddr_1d : std_logic_vector(MAX_RADIX_BITS-1 downto 0);
signal aw_bram_din_1d : std_logic_vector(15 downto 0);

signal finished : std_logic := '0';
signal finish_allowed : std_logic := '0';
signal resetted : std_logic := '0';
signal reserved_CL_for_counting : integer;

signal count_read_index : integer range 0 to MAX_FANOUT;
signal accumulation : integer;

signal fill_rate : std_logic_vector(3 downto 0);
signal fill_rate_1d : std_logic_vector(3 downto 0);
signal tuples : std_logic_vector(511 downto 0);
signal tuples_1d : std_logic_vector(511 downto 0);
signal bucket_address : std_logic_vector(ADDR_LMT-1 downto 0) := (others => '0');
signal cache_line_to_send : std_logic_vector(511 downto 0);
signal currently_reading_fill_rate : integer := 0;

signal ofifo_we :			std_logic;
signal ofifo_din :			std_logic_vector(511 + ADDR_LMT downto 0);	
signal ofifo_re :			std_logic;
signal ofifo_valid :		std_logic;
signal ofifo_dout :			std_logic_vector(511 + ADDR_LMT downto 0);
signal ofifo_count :		std_logic_vector(FIFO_DEPTH_BITS-1 downto 0);
signal ofifo_empty :		std_logic;
signal ofifo_full :			std_logic;
signal ofifo_almostfull: 	std_logic;

signal timers_written : std_logic;
signal partitioning_timer : unsigned(31 downto 0);

component my_fifo
generic(
	FIFO_WIDTH : integer := 32;
	FIFO_DEPTH_BITS : integer := 8;
	FIFO_ALMOSTFULL_THRESHOLD : integer := 220);
port(
	clk :		in std_logic;
	reset_n :	in std_logic;

	we :		in std_logic;
	din :		in std_logic_vector(FIFO_WIDTH-1 downto 0);	
	re :		in std_logic;
	valid :		out std_logic;
	dout :		out std_logic_vector(FIFO_WIDTH-1 downto 0);
	count :		out std_logic_vector(FIFO_DEPTH_BITS-1 downto 0);
	empty :		out std_logic;
	full :		out std_logic;
	almostfull: out std_logic);
end component;

component simple_dual_port_ram_single_clock
generic(
	DATA_WIDTH : integer := 32;
	ADDR_WIDTH : integer := 8);
port(
	clk :	in std_logic;
	raddr : in std_logic_vector(ADDR_WIDTH-1 downto 0);
	waddr : in std_logic_vector(ADDR_WIDTH-1 downto 0);
	data : 	in std_logic_vector(DATA_WIDTH-1 downto 0);
	we :	in std_logic;
	q : 	out std_logic_vector(DATA_WIDTH-1 downto 0));
end component;

component murmur_key32
generic (
	HASH_BITS : integer := 20);
port (
	clk : in std_logic;
	resetn : in std_logic;
	hash_select : in std_logic_vector(3 downto 0);
	req_hash : in std_logic;
	in_data : in std_logic_vector(63 downto 0);
	out_valid : out std_logic;
	out_data : out std_logic_vector(HASH_BITS + 63 downto 0));
end component;

component distributor
generic(
	MAX_RADIX_BITS : integer := 4);
port(
	clk : in std_logic;
	resetn : in std_logic;

	number_of_expected_tuples : in std_logic_vector(31 downto 0);
	radix_bits : in std_logic_vector(31 downto 0);

	ififo_re : out std_logic;
	ififo_valid : in std_logic;
	ififo_data : in std_logic_vector(MAX_RADIX_BITS + 63 downto 0);
	ififo_empty : in std_logic;
	
	ofifo_re : in std_logic;
	ofifo_valid : out std_logic;
	ofifo_dout : out std_logic_vector(4 + MAX_RADIX_BITS + 511 downto 0);
	ofifo_empty : out std_logic;
	ofifo_almostfull : out std_logic);
end component;

begin

src_bram: simple_dual_port_ram_single_clock
generic map (
	DATA_WIDTH => ADDR_LMT,
	ADDR_WIDTH => 11)
port map (
	clk => Clk_32UI,
	raddr => src_bram_raddr,
	waddr => src_bram_waddr,
	data => src_bram_din,
	we => src_bram_we,
	q => src_bram_dout);

dst_bram: simple_dual_port_ram_single_clock
generic map (
	DATA_WIDTH => ADDR_LMT,
	ADDR_WIDTH => 11)
port map (
	clk => Clk_32UI,
	raddr => dst_bram_raddr,
	waddr => dst_bram_waddr,
	data => dst_bram_din,
	we => dst_bram_we,
	q => dst_bram_dout);

GenX: for k in 0 to 7 generate
	stX : murmur_key32
	generic map (
		HASH_BITS => MAX_RADIX_BITS)
	port map (
		clk => Clk_32UI,
		resetn => test_Resetb,
		hash_select => re2xy_test_cfg(3 downto 0),
		req_hash => hash_request,
		in_data => cl_of_keys(63 + k*64 downto k*64),
		out_valid => hash_out_valid(k),
		out_data => hash_out_data(k));

	fifo_din(k) <= (hash_out_data(k)(64 + MAX_RADIX_BITS - 1 downto 64) and MASK) & hash_out_data(k)(63 downto 0);

	fifoX: my_fifo
	generic map (
		FIFO_WIDTH => MAX_RADIX_BITS + 64,
		FIFO_DEPTH_BITS => FIFO_DEPTH_BITS,
		FIFO_ALMOSTFULL_THRESHOLD => 240)
	port map (
		clk => Clk_32UI,
		reset_n => test_Resetb,

		we => hash_out_valid(k),
		din => fifo_din(k),
		re => fifo_re(k),
		valid => fifo_valid(k),
		dout => fifo_dout(k),
		count => fifo_count(k),
		empty => fifo_empty(k),
		full => fifo_full(k),
		almostfull => fifo_almostfull(k));

	distributorX: distributor
	generic map (
		MAX_RADIX_BITS => MAX_RADIX_BITS)
	port map (
		clk => Clk_32UI,
		resetn => test_Resetb,

		number_of_expected_tuples => std_logic_vector(NumberOfExpectedCacheLines),
		radix_bits => re2xy_radix_bits,

		ififo_re => fifo_re(k),
		ififo_valid => fifo_valid(k),
		ififo_data => fifo_dout(k),
		ififo_empty => fifo_empty(k),

		ofifo_re => dfifo_re(k),
		ofifo_valid => dfifo_valid(k),
		ofifo_dout => dfifo_dout(k),
		ofifo_empty => dfifo_empty(k),
		ofifo_almostfull => dfifo_almostfull(k));
end generate GenX;

already_written_bram: simple_dual_port_ram_single_clock
generic map (
	DATA_WIDTH => 16,
	ADDR_WIDTH => MAX_RADIX_BITS)
port map (
	clk => Clk_32UI,
	raddr => aw_bram_raddr,
	waddr => aw_bram_waddr,
	data => aw_bram_din,
	we => aw_bram_we,
	q => aw_bram_dout);

ofifo: my_fifo
generic map(
	FIFO_WIDTH => ADDR_LMT + 512,
	FIFO_DEPTH_BITS => FIFO_DEPTH_BITS,
	FIFO_ALMOSTFULL_THRESHOLD => 240)
port map(
	clk => Clk_32UI,
	reset_n => test_Resetb,

	we => ofifo_we,
	din => ofifo_din,
	re => ofifo_re,
	valid => ofifo_valid,
	dout => ofifo_dout,
	count => ofifo_count,
	empty => ofifo_empty,
	full => ofifo_full,
	almostfull => ofifo_almostfull);

fifos_almostfull <= fifo_almostfull(7) or fifo_almostfull(6) or fifo_almostfull(5) or fifo_almostfull(4) or fifo_almostfull(3) or fifo_almostfull(2) or fifo_almostfull(1) or fifo_almostfull(0);
fifos_count <= fifo_count(7) or fifo_count(6) or fifo_count(5) or fifo_count(4) or fifo_count(3) or fifo_count(2) or fifo_count(1) or fifo_count(0);
fifos_free_count <= (2**FIFO_DEPTH_BITS-1) - to_integer(unsigned(fifos_count));

l12ab_RdAddr <= current_RdAddr_2d;

NumberOfReadCacheLines <= unsigned(read_NumLines);

process(Clk_32UI)
variable offsetted_RdAddr : unsigned(ADDR_LMT-1 downto 0) := (others => '0');
variable offsetted_WrAddr : unsigned(ADDR_LMT-1 downto 0) := (others => '0');
variable current_aw_bram_dout : unsigned(15 downto 0) := (others => '0');
begin
if Clk_32UI'event and Clk_32UI = '1' then
----------------------------------------------------------------------------------------------------------------CONFIG BEGIN
	case to_integer(unsigned(re2xy_radix_bits)) is
		when 13 =>
			MASK <= B"1111111111111";
		when 12 =>
			MASK <= B"0111111111111";
		when 11 =>
			MASK <= B"0011111111111";
		when 10 =>
			MASK <= B"0001111111111";
		when 9 =>
			MASK <= B"0000111111111";
		when 8 =>
			MASK <= B"0000011111111";
		when 7 =>
			MASK <= B"0000001111111";
		when 6 =>
			MASK <= B"0000000111111";
		when 5 =>
			MASK <= B"0000000011111";
		when 4 =>
			MASK <= B"0000000001111";
		when others =>
			MASK <= B"1111111111111";
	end case;
	--case to_integer(unsigned(re2xy_radix_bits)) is
	--	when 12 =>
	--		MASK <= B"111111111111";
	--	when 11 =>
	--		MASK <= B"011111111111";
	--	when 10 =>
	--		MASK <= B"001111111111";
	--	when 9 =>
	--		MASK <= B"000111111111";
	--	when 8 =>
	--		MASK <= B"000011111111";
	--	when 7 =>
	--		MASK <= B"000001111111";
	--	when 6 =>
	--		MASK <= B"000000111111";
	--	when 5 =>
	--		MASK <= B"000000011111";
	--	when 4 =>
	--		MASK <= B"000000001111";
	--	when others =>
	--		MASK <= B"111111111111";
	--end case;
	NumberOfCacheLinesToRead <= unsigned(re2xy_NumLines);
	NumberOfExpectedCacheLines <= unsigned(re2xy_expected_NumLines);
	FANOUT <= to_integer(shift_left(ONE, to_integer(unsigned(re2xy_radix_bits))));
	PARTITION_SIZE <= shift_right(unsigned(re2xy_expected_NumLines), to_integer(unsigned(re2xy_radix_bits)));
	PADDING_SIZE_DIVIDER <= to_integer(unsigned(re2xy_test_cfg(7 downto 4)));
	if PARTITION_SIZE > 64 then
		PARTITION_SIZE_WITH_PADDING <= PARTITION_SIZE + shift_right(PARTITION_SIZE, PADDING_SIZE_DIVIDER);
	else
		PARTITION_SIZE_WITH_PADDING <= PARTITION_SIZE + X"00000040";
	end if;
	reserved_CL_for_counting <= to_integer(shift_right(to_unsigned(FANOUT, 32), 4));
----------------------------------------------------------------------------------------------------------------CONFIG END
	dfifos_almostfull <= dfifo_almostfull(7) or dfifo_almostfull(6) or dfifo_almostfull(5) or dfifo_almostfull(4) or dfifo_almostfull(3) or dfifo_almostfull(2) or dfifo_almostfull(1) or dfifo_almostfull(0);
	dfifos_empty <= dfifo_empty(7) and dfifo_empty(6) and dfifo_empty(5) and dfifo_empty(4) and dfifo_empty(3) and dfifo_empty(2) and dfifo_empty(1) and dfifo_empty(0);
	dfifos_empty_end <= dfifos_empty_d(15) and
						dfifos_empty_d(14) and
						dfifos_empty_d(13) and
						dfifos_empty_d(12) and
						dfifos_empty_d(11) and
						dfifos_empty_d(10) and
						dfifos_empty_d(9) and
						dfifos_empty_d(8) and
						dfifos_empty_d(7) and
						dfifos_empty_d(6) and
						dfifos_empty_d(5) and
						dfifos_empty_d(4) and
						dfifos_empty_d(3) and
						dfifos_empty_d(2) and
						dfifos_empty_d(1) and
						dfifos_empty_d(0);
	tuples <= dfifo_dout(i_4d)(511 downto 0);
	tuples_1d <= tuples;

	if test_Resetb = '0' then
		src_bram_re <= '0';
		src_bram_re_1d <= '0';
		src_bram_we <= '0';
		src_bram_raddr <= (others => '0');
		src_bram_raddr_1d <= (others => '0');
		src_bram_waddr <= (others => '0');
		src_bram_din <= (others => '0');
		src_bram_waddr_count <= (others =>'0');

		dst_bram_re <= '0';
		dst_bram_re_1d <= '0';
		dst_bram_we <= '0';
		dst_bram_raddr <= (others => '0');
		dst_bram_waddr <= (others => '0');
		dst_bram_din <= (others => '0');
		dst_bram_waddr_count <= (others => '0');

		RdSent_was_down <= '0';
		RdSent_was_down_1d <= '0';
		current_RdAddr <= (others => '0');
		current_RdAddr_1d <= (others => '0');
		current_RdAddr_2d <= (others => '0');
		current_WrAddr <= (others => '0');
		current_WrAddr_1d <= (others => '0');
		current_WrDin <= (others => '0');
		current_WrDin_1d <= (others => '0');

		i <= 0;
		i_1d <= 0;
		i_2d <= 0;
		i_3d <= 0;
		i_4d <= 0;

		if 0 <= j and j < MAX_FANOUT-1 then
			j <= j + 1;
		else
			j <= 0;
		end if;

		NumberOfRequestedLines <= (others => '0');
		NumberOfRequestedLines_1d <= (others => '0');
		NumberOfRequestedLines_1d <= (others => '0');
		NumberOfReceivedLines <= (others => '0');
		NumberOfSentLines <= (others => '0');
		NumberOfCompletedWrites <= (others => '0');

		request_issued <= '0';
		send_issued <= '0';
		send_pending <= '0';

		hash_request <= '0';
		cl_of_keys <= (others => '0');

		dfifo_re <= (others => '0');

		aw_bram_we <= '1';
		aw_bram_re <= '0';
		aw_bram_raddr <= (others => '0');
		aw_bram_waddr <= std_logic_vector(to_unsigned(j, MAX_RADIX_BITS));
		aw_bram_din <= (others => '0');

		aw_bram_re_1d <= '0';
		aw_bram_raddr_1d <= (others => '0');
		aw_bram_waddr_1d <= (others => '0');
		aw_bram_din_1d <= (others => '0');

		finished <= '0';
		finish_allowed <= '0';
		resetted <= '0';
		
		count_read_index <= 0;
		accumulation <= 0;

		fill_rate <= (others => '0');
		fill_rate_1d <= (others => '0');
		bucket_address <= (others => '0');
		cache_line_to_send <= (others => '0');
		currently_reading_fill_rate <= 0;

		dfifos_empty_d <= (others => '0');

		ofifo_we <= '0';
		ofifo_din <= (others => '0');
		ofifo_re <= '0';

		timers_written <= '0';
		partitioning_timer <= (others => '0');

		decomp_stop_sending <= '0';

		l12ab_WrAddr <= (others => '0');
		l12ab_WrTID <= (others => '0');
		l12ab_WrDin <= (others => '0');
		l12ab_WrEn <= '0';

		l12ab_RdTID <= (others => '0');
		l12ab_RdEn <= '0';

		l12ab_TestCmp <= '0';
		l12ab_ErrorInfo <= (others => '0');
		l12ab_ErrorValid <= '0';

		reset_read_NumLines <= '0';
	else
		src_bram_we <= '0';
		dst_bram_we <= '0';
		if ab2l1_CfgValid = '1' then
			if re2xy_addr_reset = X"00000000" then
				src_bram_waddr_count <= (others => '0');
				dst_bram_waddr_count <= (others => '0');
			elsif re2xy_addr_reset = X"00000001" and re2xy_src_addr /= X"00000000" then
				src_bram_we <= '1';
				src_bram_waddr <= std_logic_vector(src_bram_waddr_count);
				src_bram_din <= re2xy_src_addr;
				src_bram_waddr_count <= src_bram_waddr_count + 1;
			elsif re2xy_addr_reset = X"00000002" and re2xy_dst_addr /= X"00000000" then
				dst_bram_we <= '1';
				dst_bram_waddr <= std_logic_vector(dst_bram_waddr_count);
				dst_bram_din <= re2xy_dst_addr;
				dst_bram_waddr_count <= dst_bram_waddr_count + 1;
			end if;
		end if;

		src_bram_re <= '0';
		if re2xy_go = '1' and NumberOfRequestedLines < NumberOfCacheLinesToRead and dfifos_almostfull = '0' and ab2l1_WrAlmFull = '0' and decomp_almostfull = '0' and NumberOfRequestedLines - NumberOfReadCacheLines < fifos_free_count and NumberOfRequestedLines - NumberOfReadCacheLines < unsigned(decomp_fifos_free_count) then
			src_bram_re <= '1';
			offsetted_RdAddr := NumberOfRequestedLines + unsigned(re2xy_read_offset);
			src_bram_raddr <= std_logic_vector(offsetted_RdAddr(10 + PAGE_SIZE_IN_BITS downto PAGE_SIZE_IN_BITS));
			current_RdAddr <= std_logic_vector(offsetted_RdAddr);
			NumberOfRequestedLines <= NumberOfRequestedLines + 1;
		end if;

		decomp_stop_sending <= '0';
		if fifos_free_count < 10 or dfifos_almostfull = '1' then
			decomp_stop_sending <= '1';
		end if;

		l12ab_RdEn <= '0';
		RdSent_was_down <= '0';
		request_issued <= '0';
		if request_issued = '1' and ab2l1_RdSent = '0' then -- Request lines
			NumberOfRequestedLines <= NumberOfRequestedLines_2d;
			RdSent_was_down <= '1';
		elsif RdSent_was_down = '0' then
			if RdSent_was_down_1d = '1' then
				l12ab_RdEn <= '1';
				current_RdAddr_2d <= current_RdAddr_2d;
				request_issued <= '1';
			elsif src_bram_re_1d = '1' then
				l12ab_RdEn <= '1';
				current_RdAddr_2d <= std_logic_vector(unsigned(src_bram_dout) + unsigned(current_RdAddr_1d(PAGE_SIZE_IN_BITS-1 downto 0)));
				request_issued <= '1';
			end if;
		end if;

		RdSent_was_down_1d <= RdSent_was_down;
		current_RdAddr_1d <= current_RdAddr;
		src_bram_re_1d <= src_bram_re;
		src_bram_raddr_1d <= src_bram_raddr;
		NumberOfRequestedLines_1d <= NumberOfRequestedLines;
		NumberOfRequestedLines_2d <= NumberOfRequestedLines_1d;

		hash_request <= '0';
		if ab2l1_RdRspValid = '1' then -- Receive lines
			NumberOfReceivedLines <= NumberOfReceivedLines + 1;
			cl_of_keys <= ab2l1_RdData;
			hash_request <= '1';
		end if;

		if i = 7 then
			i <= 0;
		else
			i <= i + 1;
		end if;
		dfifo_re <= (others => '0');
		if dfifo_empty(i) = '0' and ofifo_almostfull = '0' then
			dfifo_re(i) <= '1';
		end if;

		aw_bram_re <= '0';
		if dfifo_valid(i_4d) = '1' then
			aw_bram_re <= '1';
			aw_bram_raddr(MAX_RADIX_BITS-1 downto 0) <= dfifo_dout(i_4d)(MAX_RADIX_BITS + 511 downto 512);
			fill_rate <= dfifo_dout(i_4d)(4 + MAX_RADIX_BITS + 511 downto MAX_RADIX_BITS + 512);
			
		elsif finished = '1' and count_read_index < FANOUT then
			aw_bram_re <= '1';
			aw_bram_raddr <= std_logic_vector(to_unsigned(count_read_index, MAX_RADIX_BITS));
			count_read_index <= count_read_index + 1;
		end if;

		if dfifo_empty(0) = '0' and dfifo_empty(1) = '0' and dfifo_empty(2) = '0' and dfifo_empty(3) = '0' and dfifo_empty(4) = '0' and dfifo_empty(5) = '0' and dfifo_empty(6) = '0' and dfifo_empty(7) = '0' then
			finish_allowed <= '1';
		end if;
		if NumberOfReceivedLines >= NumberOfExpectedCacheLines and (NumberOfSentLines = NumberOfCompletedWrites) and dfifos_empty_end = '1' and finish_allowed = '1' then
			finished <= '1';
		end if;

		reset_read_NumLines <= '0';
		aw_bram_we <= '0';
		currently_reading_fill_rate <= 0;
		if aw_bram_re_1d = '1' then
			if finished = '0' then
				if aw_bram_raddr_1d = aw_bram_waddr then
					current_aw_bram_dout := unsigned(aw_bram_din);
				elsif aw_bram_raddr_1d = aw_bram_waddr_1d then
					current_aw_bram_dout := unsigned(aw_bram_din_1d);
				else
					current_aw_bram_dout := unsigned(aw_bram_dout);
				end if;
				bucket_address <= std_logic_vector(to_unsigned(to_integer(current_aw_bram_dout) + to_integer(PARTITION_SIZE_WITH_PADDING)*to_integer(unsigned(aw_bram_raddr_1d)) + reserved_CL_for_counting, ADDR_LMT));
				cache_line_to_send <= tuples_1d;
				currently_reading_fill_rate <= to_integer(unsigned(fill_rate_1d));
				aw_bram_we <= '1';
				aw_bram_waddr <= aw_bram_raddr_1d;
				aw_bram_din <= std_logic_vector(current_aw_bram_dout + 1);
			else
				aw_bram_we <= '1';
				aw_bram_waddr <= aw_bram_raddr_1d;
				aw_bram_din <= (others => '0');
				accumulation <= accumulation + to_integer(unsigned(aw_bram_dout));
				case aw_bram_raddr_1d(3 downto 0) is
					when B"0000" =>
						cache_line_to_send(31 downto 0) <= X"0000"&aw_bram_dout;
					when B"0001" =>
						cache_line_to_send(63 downto 32) <= X"0000"&aw_bram_dout;
					when B"0010" =>
						cache_line_to_send(95 downto 64) <= X"0000"&aw_bram_dout;
					when B"0011" =>
						cache_line_to_send(127 downto 96) <= X"0000"&aw_bram_dout;
					when B"0100" =>
						cache_line_to_send(159 downto 128) <= X"0000"&aw_bram_dout;
					when B"0101" =>
						cache_line_to_send(191 downto 160) <= X"0000"&aw_bram_dout;
					when B"0110" =>
						cache_line_to_send(223 downto 192) <= X"0000"&aw_bram_dout;
					when B"0111" =>
						cache_line_to_send(255 downto 224) <= X"0000"&aw_bram_dout;
					when B"1000" =>
						cache_line_to_send(287 downto 256) <= X"0000"&aw_bram_dout;
					when B"1001" =>
						cache_line_to_send(319 downto 288) <= X"0000"&aw_bram_dout;
					when B"1010" =>
						cache_line_to_send(351 downto 320) <= X"0000"&aw_bram_dout;
					when B"1011" =>
						cache_line_to_send(383 downto 352) <= X"0000"&aw_bram_dout;
					when B"1100" =>
						cache_line_to_send(415 downto 384) <= X"0000"&aw_bram_dout;
					when B"1101" =>
						cache_line_to_send(447 downto 416) <= X"0000"&aw_bram_dout;
					when B"1110" =>
						cache_line_to_send(479 downto 448) <= X"0000"&aw_bram_dout;
					when B"1111" =>
						bucket_address(MAX_RADIX_BITS-5 downto 0) <= aw_bram_raddr_1d(MAX_RADIX_BITS-1 downto 4);
						bucket_address(ADDR_LMT-1 downto MAX_RADIX_BITS-4) <= (others => '0');
						cache_line_to_send(511 downto 480) <= X"0000"&aw_bram_dout;
						currently_reading_fill_rate <= 8; -- Mock fill rate, just to have it written to ofifo
						if count_read_index = FANOUT then
							resetted <= '1';
						end if;
					when others =>
						--cache_line_to_send <= (others => '0');
				end case;
			end if;
		end if;
		if finished = '1' and resetted = '1' and timers_written = '0' then
			timers_written <= '1';
			bucket_address <= std_logic_vector(to_unsigned(to_integer(PARTITION_SIZE_WITH_PADDING)*FANOUT - 1 + reserved_CL_for_counting, ADDR_LMT));
			cache_line_to_send(63 downto 0) <= (others => '0');
			cache_line_to_send(31 downto 0) <= std_logic_vector(partitioning_timer);
			currently_reading_fill_rate <= 1;
		end if;
		
		ofifo_we <= '0';
		if currently_reading_fill_rate > 0 then -- Write to Send FIFO
			ofifo_we <= '1';
			if currently_reading_fill_rate = 8 then
				ofifo_din <= bucket_address & cache_line_to_send(511 downto 0);
			elsif currently_reading_fill_rate = 7 then
				ofifo_din <= bucket_address & X"00000000"&re2xy_dummy_key & cache_line_to_send(447 downto 0);
			elsif currently_reading_fill_rate = 6 then
				ofifo_din <= bucket_address & X"00000000"&re2xy_dummy_key & X"00000000"&re2xy_dummy_key & cache_line_to_send(383 downto 0);
			elsif currently_reading_fill_rate = 5 then
				ofifo_din <= bucket_address & X"00000000"&re2xy_dummy_key & X"00000000"&re2xy_dummy_key & X"00000000"&re2xy_dummy_key & cache_line_to_send(319 downto 0);
			elsif currently_reading_fill_rate = 4 then
				ofifo_din <= bucket_address & X"00000000"&re2xy_dummy_key & X"00000000"&re2xy_dummy_key & X"00000000"&re2xy_dummy_key & X"00000000"&re2xy_dummy_key & cache_line_to_send(255 downto 0);
			elsif currently_reading_fill_rate = 3 then
				ofifo_din <= bucket_address & X"00000000"&re2xy_dummy_key & X"00000000"&re2xy_dummy_key & X"00000000"&re2xy_dummy_key & X"00000000"&re2xy_dummy_key & X"00000000"&re2xy_dummy_key & cache_line_to_send(191 downto 0);
			elsif currently_reading_fill_rate = 2 then
				ofifo_din <= bucket_address & X"00000000"&re2xy_dummy_key & X"00000000"&re2xy_dummy_key & X"00000000"&re2xy_dummy_key & X"00000000"&re2xy_dummy_key & X"00000000"&re2xy_dummy_key & X"00000000"&re2xy_dummy_key & cache_line_to_send(127 downto 0);
			elsif currently_reading_fill_rate = 1 then
				ofifo_din <= bucket_address & X"00000000"&re2xy_dummy_key & X"00000000"&re2xy_dummy_key & X"00000000"&re2xy_dummy_key & X"00000000"&re2xy_dummy_key & X"00000000"&re2xy_dummy_key & X"00000000"&re2xy_dummy_key & X"00000000"&re2xy_dummy_key & cache_line_to_send(63 downto 0);
			end if;
		end if;
		
		ofifo_re <= '0';
		if ofifo_empty = '0' and ab2l1_WrAlmFull = '0' and send_pending = '0' then -- Send lines
			ofifo_re <= '1';	
		end if;
		dst_bram_re <= '0';
		if ofifo_valid = '1' then
			dst_bram_re <= '1';
			offsetted_WrAddr := unsigned(ofifo_dout(511+ADDR_LMT downto 512)) + unsigned(re2xy_write_offset);
			dst_bram_raddr <= std_logic_vector(offsetted_WrAddr(10+PAGE_SIZE_IN_BITS downto PAGE_SIZE_IN_BITS));
			current_WrAddr <= std_logic_vector(offsetted_WrAddr);
            current_WrDin <= ofifo_dout(511 downto 0);
		end if;
		
		l12ab_WrEn <= '0';
		if dst_bram_re_1d = '1' then
			l12ab_WrEn <= '1';
			l12ab_WrAddr <= std_logic_vector(unsigned(dst_bram_dout) + unsigned(current_WrAddr_1d(PAGE_SIZE_IN_BITS-1 downto 0)));
			l12ab_WrDin <= current_WrDin_1d;
			NumberOfSentLines <= NumberOfSentLines + 1;
		end if;

		dst_bram_re_1d <= dst_bram_re;
		current_WrAddr_1d <= current_WrAddr;
		current_WrDin_1d <= current_WrDin;

		if ab2l1_WrRspValid = '1' then -- Follow completed writes
			NumberOfCompletedWrites <= NumberOfCompletedWrites + 1;
		end if;

		l12ab_TestCmp <= '0';
		if resetted = '1' and timers_written = '1' and ofifo_empty = '1' and ofifo_valid = '0' and ofifo_we = '0' and ofifo_re = '0' and dst_bram_re = '0' and dst_bram_re_1d = '0' and NumberOfSentLines = NumberOfCompletedWrites and NumberOfSentLines >= NumberOfExpectedCacheLines and NumberOfReadCacheLines = NumberOfCacheLinesToRead then
			l12ab_TestCmp <= '1';
		end if;

		i_1d <= i;
		i_2d <= i_1d;
		i_3d <= i_2d;
		i_4d <= i_3d;
		aw_bram_re_1d <= aw_bram_re;
		aw_bram_raddr_1d <= aw_bram_raddr;
		aw_bram_waddr_1d <= aw_bram_waddr;
		aw_bram_din_1d <= aw_bram_din;
		fill_rate_1d <= fill_rate;

		dfifos_empty_d(0) <= dfifos_empty;
		dfifos_empty_d(1) <= dfifos_empty_d(0);
		dfifos_empty_d(2) <= dfifos_empty_d(1);
		dfifos_empty_d(3) <= dfifos_empty_d(2);
		dfifos_empty_d(4) <= dfifos_empty_d(3);
		dfifos_empty_d(5) <= dfifos_empty_d(4);
		dfifos_empty_d(6) <= dfifos_empty_d(5);
		dfifos_empty_d(7) <= dfifos_empty_d(6);
		dfifos_empty_d(8) <= dfifos_empty_d(7);
		dfifos_empty_d(9) <= dfifos_empty_d(8);
		dfifos_empty_d(10) <= dfifos_empty_d(9);
		dfifos_empty_d(11) <= dfifos_empty_d(10);
		dfifos_empty_d(12) <= dfifos_empty_d(11);
		dfifos_empty_d(13) <= dfifos_empty_d(12);
		dfifos_empty_d(14) <= dfifos_empty_d(13);
		dfifos_empty_d(15) <= dfifos_empty_d(14);

		if re2xy_go = '1' then
			partitioning_timer <= partitioning_timer + 1;
		end if;

	end if;
end if;
end process;

end behavioral;