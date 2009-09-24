Ffs: module
{
	PATH:	con "/dis/lib/ffs.dis";
	dflag:	int;
	init:	fn();


	# disklabel

	Disklabelmagic: con int 16r82564557;
	Disklabellen: con 8*1024;

	Disklabel: adt {
		magic:		int;
		drvtype,
		drvsubtype:	int;
		typename:	string;
		packname:	string;
		secsize,
		nsectors,
		ntracks,
		ncyls,
		secpercyl,
		secperunit:	int;
		sparespertrack,
		sparespercyl:	int;
		altcyls:	int;
		rpm,
		interleave,
		trackskew,
		cylskew,
		headswitch,
		trkseek,
		flags:		int;
		drivedata:	array of int;
		secperunith,
		version:	int;
		spare:		array of int;
		magic2,
		checksum:	int;
		nparts,
		bbsize,
		sbsize:		int;
		parts:		array of ref Dlpart;

		parse:	fn(buf: array of byte): (ref Disklabel, string);
		read:	fn(fd: ref Sys->FD): (ref Disklabel, string);
		get:	fn(fd: ref Sys->FD, label: int): (ref Disklabel, ref Dlpart, big, string);
	};

	Dlpart: adt {
		nsectors,
		firstsector:	big;
		fstype,
		fragblock,
		ncylpergroup:	int;
	};

	FSunused,
	FSswap,
	FSv6,
	FSv7,
	FSsysv,
	FSv71k,
	FSv8,
	FSbsdffs,
	FSmsdos,
	FSbsdlfs,
	FSother,
	FShpfs,
	FSiso9660,
	FSboot,
	FSados,
	FShfs,
	FSadfs,
	FSext2fs,
	FSccd,
	FSraid,
	FSntfs,
	FSudf:	con iota;

	fstypes: array of string;


	# ffs

	Supermagic: con 16r011954;
	FSisclean,
	FSwasclean:	con 1+iota;

	Csum: adt {
		ndir,
		nfreeblocks,
		nfreeinodes,
		nfreefrags:	int;
	};

	Csumtotal: adt {
		ndir,
		nfreeblocks,
		nfreeinodes,
		nfreefrags:	big;
		spare:		array of byte; # 4*8
	};
	
	Superlen: con 8192;
	Superoff: con big 8192;
	Super: adt {
		firstfield,
		unused1,
		superblock,
		offcyl,
		offinode,
		offdata,
		cgoffset,
		cgmask,
		ffs1time,
		ffs1nblocks,
		ffs1ndblocks,
		ncylg,
		blocksize,
		fragsize,
		nblockfrags,
		minfree,
		rotdelay,
		rps,
		bmask,
		fmask,
		bshift,
		fshift,
		maxcontig,
		maxcylgblocks,
		fragshift,
		fsbtodbshift,
		supersize,
		csummask,
		csumshift,
		nindblocks,
		nblockinodes,
		nspf,
		optim,
		ntracksectors,
		interleave,
		trackskew:	int;
		id:		big;
		ffs1csumaddr,
		csumsize,
		cgbsize,
		ncyltracks,
		ntracksectors2,
		ncylsectors,
		ncyl,
		ngroupcyls,
		ngroupinodes,
		nfraggrpblocks:	int;
		ffs1cylsum:	Csum;
		supermodflag,
		clean,
		romntflag,
		ffs1flags:	int;
		fsmnt:		string;
		volname:	string;
		uid:		big;

		pad:	int;
		cylgrotor:	int;
		ocsp:		array of byte;	# 128
		ptrs:		array of byte;	# 5 void*...
		ncyclecyl:	int;
		maxbsize:	int;
		spareconf:	array of byte;	# 17*8
		stdsuperoff:	big;
		cylsum:		Csumtotal;
		lastwrite,
		nblocks,
		ndblocks,
		cylgsumaddr,
		npendingfreeblocks:	big;
		npendingfreeincodes:	int;
		snap:		array of byte;	# 20*4
		expavgfilesize:	int;
		expavgdirfiles:	int;
		sparecon:	array of byte;	# 26*4
		flags,
		lastfscktime,
		contigsumsize,
		maxinlinesymlinklen,
		inodefmt:	int;
		maxfilesize,
		qbmask,
		qfmask:		big;
		state:		int;
		postableformat:	int;
		nrotpos:	int;
		postableoff:	int;
		nrotblocks:	int;
		magic:		int;
		space:		int;

		parse:	fn(buf: array of byte): (ref Super, string);
		read:	fn(fd: ref Sys->FD, off: big): (ref Super, string);
		text:	fn(s: self ref Super): string;
	};

	Cgmagic:	con 16r00090255;
	Cg: adt {
		firstfield:	int;
		magic,
		lastwrite,
		index:	int;
		ncyl,
		niblocks,
		ndblocks:	int;
		cs:	Csum;
		rotor,
		frotor,
		irotor:		int;
		fragcounts:	array of int;	# 8
		nblocks,
		freeblockpos,
		iusedoff,
		ifreeoff,
		nextfreeoff,
		clustersumoff,
		nclusters,
		ffs2niblocks,
		lastinitinode:	int;
		spare0:		array of int;	# 3
		ffs2lastwrite:	big;
		spare1:		array of big;	# 3

		parse:	fn(buf: array of byte): (ref Cg, string);
		read:	fn(fd: ref Sys->FD, size: int, off: big): (ref Cg, string);
		text:	fn(c: self ref Cg): string;
	};

	# Inode.mode
	FTmask:	con 8r17<<12;
	FTfifo:	con 8r01<<12;
	FTchr:	con 8r02<<12;
	FTdir:	con 8r04<<12;
	FTblk:	con 8r06<<12;
	FTreg:	con 8r10<<12;
	FTlnk:	con 8r12<<12;
	FTsock:	con 8r14<<12;
	FTwht:	con 8r16<<12;
	
	Inodelen: con 128;
	Rootinode: con 2;
	Inode: adt {
		mode,
		nlink:	int;
		oldids0,
		oldids1:	int;
		length:	big;
		atime,
		mtime,
		ctime:	int;
		blocks:	array of int;	# 12
		indblocks:	array of int;	# 3
		blockbuf:	array of byte; # used for symlink path or devices
		flags,
		nblocks,
		gen,
		uid,
		gid:	int;
		spare0,
		spare1:	int;

		read:	fn(fd: ref Sys->FD, off: big, s: ref Super): (ref Inode, string);
		parse:	fn(buf: array of byte): (ref Inode, string);
		text:	fn(i: self ref Inode): string;
	};

	Maxnamelen: con 255;
	Entry: adt {
		inode:	int;
		length:	int;
		dtype:	int;
		name:	string;

		parse:	fn(buf: array of byte, o: int): (ref Entry, int, string);
		text:	fn(e: self ref Entry): string;
	};

	Inodedir: adt {
		i:	ref Inode;
		offset:	big;	# styx offset

		next:	ref Sys->Dir;
		b:	big;	# current directory block number
		bo:	int;	# offset in block
		buf:	array of byte;	# directory block
	};

	Part: adt {
		off:	big;
		fd:	ref Sys->FD;
		s:	ref Super;
		cg:	ref Cg;
		root:	ref Inode;
		bsize:	int;
		fsize:	int;

		init:	fn(fd: ref Sys->FD, off: big): (ref Part, string);
		getblock:	fn(p: self ref Part, i: ref Inode, buf: array of byte, bn: int): string;
		inodewalk:	fn(p: self ref Part, i: ref Inode, elem: string): (ref Inode, ref Entry, string);
		inoderead:	fn(p: self ref Part, i: ref Inode, n: int, o: big): (array of byte, string);
		inodeget:	fn(p: self ref Part, i: int): (ref Inode, string);
		inodedir:	fn(p: self ref Part, i: ref Inode): (ref Inodedir, string);
		dirpeek:	fn(p: self ref Part, id: ref Inodedir, o: big): (ref Sys->Dir, string);
		dirnext:	fn(p: self ref Part, id: ref Inodedir, o: big): (ref Sys->Dir, string);
	};

	inodereadn:	fn(fd: ref Sys->FD, off: big, bsize: int, i: ref Inode, buf: array of byte, n: int, o: big): int;
	getblock:	fn(fd: ref Sys->FD, off: big, i: ref Inode, buf: array of byte, bn: int, bsize: int): int;
	readblock:	fn(fd: ref Sys->FD, off: big, buf: array of byte, bsize: int, bn: int): string;
};
