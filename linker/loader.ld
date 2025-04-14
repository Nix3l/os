ENTRY(enter)
SECTIONS {
	. = 0x0;
	.text :
	{
        *(.boot)
		*(.text)
	}
}
