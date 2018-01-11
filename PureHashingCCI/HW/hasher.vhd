library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hasher is
generic(
	PEND_THRESH : integer := 1;
	ADDR_LMT : integer := 20;
	MDATA : integer := 14);
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
	ab2l1_RdRsp :		in std_logic_vector(13 downto 0);			--read response header
	ab2l1_RdRspAddr : 	in std_logic_vector(ADDR_LMT-1 downto 0);	--read response address
	ab2l1_RdData :		in std_logic_vector(511 downto 0);			--read data
	ab2l1_stallRd :		in std_logic;								--stall read requests FOR LPBK1

	ab2l1_WrRspValid :	in std_logic;								--write response valid
	ab2l1_WrRsp :		in std_logic_vector(13 downto 0);			--write response header
	ab2l1_WrRspAddr :	in std_logic_vector(ADDR_LMT-1 downto 0);	--write response address

	re2xy_go : 			in std_logic;								--start the test
	re2xy_NumLines :	in std_logic_vector(31 downto 0);			--number of cache lines
	re2xy_dummy_key :	in std_logic_vector(31 downto 0);
	re2xy_Cont :		in std_logic;								--continuous mode

	l12ab_TestCmp : 	out std_logic;								--test completion flag
	l12ab_ErrorInfo :	out std_logic_vector(255 downto 0);			--error information
	l12ab_ErrorValid :	out std_logic;								--test has detected an error

	test_Resetb : 		in std_logic);
end hasher;

architecture behavioral of hasher is

constant FIFO_DEPTH_BITS : integer := PEND_THRESH + 1;

signal NumberOfCacheLines : integer := 0;
signal NumberOfRequestedLines : integer := 0;
signal NumberOfReceivedLines : integer := 0;
signal NumberOfSentLines : integer := 0;
signal NumberOfCompletedWrites : integer := 0;

signal request_issued : std_logic := '0';
signal send_issued : std_logic := '0';
signal send_pending : std_logic := '0';

type hash_data_type is array (7 downto 0) of std_logic_vector(31 downto 0);

signal hash_request : std_logic;
signal cl_of_keys : std_logic_vector(511 downto 0);
signal hash_out_valid : std_logic_vector(7 downto 0);
signal hash_out_data : hash_data_type;

signal murmur_hash_request : std_logic;
signal murmur_cl_of_keys : std_logic_vector(511 downto 0);
signal murmur_hash_out_valid : std_logic_vector(7 downto 0);
signal murmur_hash_out_data : hash_data_type;

signal st_hash_request : std_logic;
signal st_populate : std_logic;
signal st_cl_of_keys : std_logic_vector(511 downto 0);
signal st_hash_out_valid : std_logic_vector(7 downto 0);
signal st_hash_out_data : hash_data_type;

signal cl_to_send : std_logic_vector(511 downto 0);
signal cl_to_send_1d : std_logic_vector(511 downto 0);
signal cl_to_send_2d : std_logic_vector(511 downto 0);

signal afifo_we :			std_logic;
signal afifo_din :			std_logic_vector(ADDR_LMT-1 downto 0);	
signal afifo_re :			std_logic;
signal afifo_valid :		std_logic;
signal afifo_dout :			std_logic_vector(ADDR_LMT-1 downto 0);
signal afifo_count :		std_logic_vector(FIFO_DEPTH_BITS-1 downto 0);
signal afifo_empty :		std_logic;
signal afifo_full :			std_logic;
signal afifo_almostfull: 	std_logic;

signal ofifo_we :			std_logic;
signal ofifo_din :			std_logic_vector(511 + ADDR_LMT downto 0);	
signal ofifo_re :			std_logic;
signal ofifo_valid :		std_logic;
signal ofifo_dout :			std_logic_vector(511 + ADDR_LMT downto 0);
signal ofifo_count :		std_logic_vector(FIFO_DEPTH_BITS-1 downto 0);
signal ofifo_empty :		std_logic;
signal ofifo_full :			std_logic;
signal ofifo_almostfull: 	std_logic;

component spl_fifo
generic(
	FIFO_WIDTH : integer := 32;
	FIFO_DEPTH_BITS : integer := 8;
	FIFO_ALMOSTFULL_THRESHOLD : integer := 180);
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

component murmur_key64
port (
	clk : in std_logic;
	resetn : in std_logic;
	req_hash : in std_logic;
	in_data : in std_logic_vector(63 downto 0);
	out_valid : out std_logic;
	out_data : out std_logic_vector(31 downto 0));
end component;

component simple_tabulation_key64
port (
	clk : in std_logic;
	resetn : in std_logic;
	req_hash : in std_logic;
	populate : in std_logic;
	in_data : in std_logic_vector(63 downto 0);
	out_valid : out std_logic;
	out_data : out std_logic_vector(31 downto 0));
end component;

begin

GenX: for k in 0 to 7 generate
	murmurX : murmur_key64 
	port map(
		clk => Clk_32UI,
		resetn => test_Resetb,
		req_hash => murmur_hash_request,
		in_data => murmur_cl_of_keys(63 + k*64 downto k*64),
		out_valid => murmur_hash_out_valid(k),
		out_data => murmur_hash_out_data(k));

	stX : simple_tabulation_key64
	port map(
		clk => Clk_32UI,
		resetn => test_Resetb,
		req_hash => st_hash_request,
		populate => st_populate,
		in_data => st_cl_of_keys(63 + k*64 downto k*64),
		out_valid => st_hash_out_valid(k),
		out_data => st_hash_out_data(k));
end generate GenX;

afifo: spl_fifo
generic map(
	FIFO_WIDTH => ADDR_LMT,
	FIFO_DEPTH_BITS => FIFO_DEPTH_BITS,
	FIFO_ALMOSTFULL_THRESHOLD => 2**FIFO_DEPTH_BITS-50)
port map(
	clk => Clk_32UI,
	reset_n => test_Resetb,

	we => afifo_we,
	din => afifo_din,
	re => afifo_re,
	valid => afifo_valid,
	dout => afifo_dout,
	count => afifo_count,
	empty => afifo_empty,
	full => afifo_full,
	almostfull => afifo_almostfull);

ofifo: spl_fifo
generic map(
	FIFO_WIDTH => ADDR_LMT + 512,
	FIFO_DEPTH_BITS => FIFO_DEPTH_BITS,
	FIFO_ALMOSTFULL_THRESHOLD => 2**FIFO_DEPTH_BITS-50)
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

NumberOfCacheLines <= to_integer(unsigned(re2xy_NumLines));

process(Clk_32UI)
begin
if Clk_32UI'event and Clk_32UI = '1' then
	if test_Resetb = '0' then
		murmur_hash_request <= '0';
		murmur_cl_of_keys <= (others => '0');

		st_hash_request <= '0';
		st_populate <= '0';
		st_cl_of_keys <= (others => '0');

		hash_out_valid <= (others => '0');
		hash_out_data <= (others => (others => '0'));
	else
		if re2xy_dummy_key = X"00000001" then
			murmur_hash_request <= hash_request;
			murmur_cl_of_keys <= cl_of_keys;
			hash_out_valid <= murmur_hash_out_valid;
			hash_out_data <= murmur_hash_out_data;

			st_hash_request <= '0';
			st_populate <= '0';
			st_cl_of_keys <= (others => '0');
		elsif re2xy_dummy_key = X"00000002" then
			murmur_hash_request <= '0';
			murmur_cl_of_keys <= (others => '0');

			st_hash_request <= hash_request;
			st_populate <= '0';
			st_cl_of_keys <= cl_of_keys;
			hash_out_valid <= st_hash_out_valid;
			hash_out_data <= st_hash_out_data;
		elsif re2xy_dummy_key = X"EEEEEEEE" then
			murmur_hash_request <= '0';
			murmur_cl_of_keys <= (others => '0');

			st_hash_request <= hash_request;
			st_populate <= '1';
			st_cl_of_keys <= cl_of_keys;
			hash_out_valid <= (others => '0');
			hash_out_data <= (others => (others => '0'));
		else
			murmur_hash_request <= '0';
			murmur_cl_of_keys <= (others => '0');

			st_hash_request <= '0';
			st_populate <= '0';
			st_cl_of_keys <= (others => '0');

			hash_out_valid <= (others => '0');
			hash_out_data <= (others => (others => '0'));
		end if;
	end if;
end if;
end process;

process(Clk_32UI)
begin
if Clk_32UI'event and Clk_32UI = '1' then
	if test_Resetb = '0' then
		NumberOfRequestedLines <= 0;
		NumberOfReceivedLines <= 0;
		NumberOfSentLines <= 0;
		NumberOfCompletedWrites <= 0;

		request_issued <= '0';
		send_issued <= '0';
		send_pending <= '0';

		hash_request <= '0';

		cl_to_send <= (others => '0');
		cl_to_send_1d <= (others => '0');
		cl_to_send_2d <= (others => '0');

		afifo_we <= '0';
		afifo_din <= (others => '0');
		afifo_re <='0';

		ofifo_we <= '0';
		ofifo_din <= (others => '0');
		ofifo_re <= '0';

		l12ab_WrAddr <= (others => '0');
		l12ab_WrTID <= (others => '0');
		l12ab_WrDin <= (others => '0');
		l12ab_WrEn <= '0';

		l12ab_RdAddr <= (others => '0');
		l12ab_RdTID <= (others => '0');
		l12ab_RdEn <= '0';

		l12ab_TestCmp <= '0';
		l12ab_ErrorInfo <= (others => '0');
		l12ab_ErrorValid <= '0';
	else
		l12ab_RdEn <= '0';
		request_issued <= '0';
		if re2xy_go = '1' then -- Request lines
			if request_issued = '1' and ab2l1_RdSent = '0' then
				NumberOfRequestedLines <= NumberOfRequestedLines - 1;
			elsif NumberOfRequestedLines < NumberOfCacheLines  and ofifo_almostfull = '0' and afifo_almostfull = '0' and ab2l1_WrAlmFull = '0' then
				l12ab_RdEn <= '1';
				request_issued <= '1';
				l12ab_RdAddr <= std_logic_vector(to_unsigned(NumberOfRequestedLines, ADDR_LMT));
				l12ab_RdTID <= std_logic_vector(to_unsigned(NumberOfRequestedLines, 14));
				NumberOfRequestedLines <= NumberOfRequestedLines + 1;
			end if;
		end if;

		hash_request <= '0';
		afifo_we <= '0';
		if ab2l1_RdRspValid = '1' then -- Receive lines
			NumberOfReceivedLines <= NumberOfReceivedLines + 1;
			cl_of_keys <= ab2l1_RdData;
			hash_request <= '1';
			if st_populate = '0' then
				afifo_we <= '1';
				afifo_din <= ab2l1_RdRspAddr;
			end if;
		end if;

		afifo_re <= '0';
		if hash_out_valid(0) = '1' then
			afifo_re <= '1';
			cl_to_send <= 	X"00000000" & hash_out_data(7) & 
							X"00000000" & hash_out_data(6) & 
							X"00000000" & hash_out_data(5) & 
							X"00000000" & hash_out_data(4) & 
							X"00000000" & hash_out_data(3) & 
							X"00000000" & hash_out_data(2) & 
							X"00000000" & hash_out_data(1) & 
							X"00000000" & hash_out_data(0);
		end if;

		ofifo_we <= '0';
		if afifo_valid = '1' then
			ofifo_we <= '1';
			ofifo_din <= afifo_dout & cl_to_send_2d;
		end if;


		ofifo_re <= '0';
		if ofifo_empty = '0' and ab2l1_WrAlmFull = '0' and send_pending = '0' then -- Send lines
			ofifo_re <= '1';	
		end if;
		l12ab_WrEn <= '0';
		send_issued <= '0';
		if ofifo_valid = '1' then
			l12ab_WrEn <= '1';
			send_issued <= '1';
			l12ab_WrAddr <= ofifo_dout(511+ADDR_LMT downto 512);
			l12ab_WrTID <= std_logic_vector(to_unsigned(NumberOfSentLines, 14));
            l12ab_WrDin <= ofifo_dout(511 downto 0);
            NumberOfSentLines <= NumberOfSentLines + 1;
		end if;
		if send_pending = '1' and ab2l1_WrSent = '1' then
			send_pending <= '0';
			l12ab_WrEn <= '1';
			send_issued <= '1';
		end if;
		if send_issued = '1' and ab2l1_WrSent = '0' then
			send_pending <= '1';
		end if;

		if ab2l1_WrRspValid = '1' then -- Follow completed writes
			NumberOfCompletedWrites <= NumberOfCompletedWrites + 1;
		end if;

		l12ab_TestCmp <= '0';
		if ofifo_empty = '1' and ofifo_valid = '0' and ofifo_we = '0' and ofifo_re = '0' and NumberOfSentLines = NumberOfCompletedWrites and NumberOfSentLines = NumberOfCacheLines then
			l12ab_TestCmp <= '1';
		end if;
		if st_populate = '1' and NumberOfReceivedLines = NumberOfCacheLines then
			l12ab_TestCmp <= '1';
		end if;

		cl_to_send_1d <= cl_to_send;
		cl_to_send_2d <= cl_to_send_1d;

	end if;
end if;
end process;

end behavioral;