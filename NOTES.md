Pages are 8k (8192 bytes).


Dictionary pages
----------------

```
4	cookie          	(the four bytes comprising the string: "RDCT")
4	padding				(reserved)
8	timestamp       	(NSDate timeIntervalSince1970, stored as a big-endian integer)
8	prev_page_id		(the page number of the previous linked dictionary page, stored as a big-endian integer)
*	DATA
```

The `DATA` field contains a list of key-value pairs encoded as follows:

```
1	key flags			
4	(kl) key length		
kl	key bytes			
1	value flags			
4	(vl) value length	
vl	value bytes			
```

The key and value flags bytes are defined by the `GTWAOFDictionaryTermFlag` enum, and allow indicating how the bytes field is to be interpreted.

* GTWAOFDictionaryTermFlagCompressed indicates that the bytes are gzip compressed.
* GTWAOFDictionaryTermFlagExtendedPage indicates that the bytes represent a (big-endian encoded) page number of a Value page.

Quads pages
-----------

```
4	cookie				(the four bytes comprising the string: "RQDS")
4	padding				(reserved)
8	timestamp			(NSDate timeIntervalSince1970, stored as a big-endian integer)
8	prev_page_id		(the page number of the previous linked quads page, stored as a big-endian integer)
8	count				(the number of quads in this page, stored as a big-endian integer)
*	DATA
```

The `DATA` field contains a list of *count* quads, encoded in 32-bytes (4 8-byte term IDs that are encoded as the objects in the corresponding dictionary pages whose keys are N-Triples encoded RDF term strings).

Value pages
-----------

```
4	cookie				(the four bytes comprising the string: "RVAL")
4	padding				(reserved)
8	timestamp			(NSDate timeIntervalSince1970, stored as a big-endian integer)
8	prev_page_id		(the page number of the previous linked value page, stored as a big-endian integer)
8	(vl) value length	(the number of quads in this page, stored as a big-endian integer)
vl	value bytes			
```

