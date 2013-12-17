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

The `DATA` field contains a list of key-value pairs. The first byte of each pair indicates its encoding.

```
1	key flags			
```

If the key flags byte does not have the `GTWAOFDictionaryTermFlagExtendedPagePair` bit set, the pair is stored inline as follows:

```
4	(kl) key length		
kl	key bytes			
1	value flags			
4	(vl) value length	
vl	value bytes			
```

If the key flags byte has the `GTWAOFDictionaryTermFlagExtendedPagePair` bit set, then the pair is stored encoded in a Value page (described below). The value page ID is encoded following the key flags:

```
4	(kl) key length		(the integer 8, stored as a big-endian integer)
8	page_id				(the page number of the Value page storing the packed pair, stored as a big-endian integer)
```

The data stored in the value page(s) pointed to by `page_id` will be packed using the same structure described above.
That is, it will encode the values for `key  flags`, `key length`, `key bytes`, `value flags`, `value length`, and `value bytes`.

The key and value flags bytes are defined by the `GTWAOFDictionaryTermFlag` enum, and allow indicating how the bytes field is to be interpreted.

* GTWAOFDictionaryTermFlagCompressed indicates that the bytes are gzip compressed.
* GTWAOFDictionaryTermFlagExtendedPagePair indicates that the pair is encoded in a separate values page (as described above).

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

