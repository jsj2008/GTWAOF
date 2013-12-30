//
//  NSData+GTWTerm.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/27/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

#import "NSData+GTWTerm.h"

#import <GTWSWBase/GTWIRI.h>
#import <GTWSWBase/GTWLiteral.h>
#import <GTWSWBase/GTWBlank.h>
#import <GTWSWBase/GTWVariable.h>
#import <SPARQLKit/SPKTurtleParser.h>
#import <SPARQLKit/SPKNTriplesSerializer.h>

@implementation NSData (GTWTerm)

+ (NSData*) gtw_dataFromTerm:(id<GTWTerm>)term {
    NSMutableData* d    = [NSMutableData data];
//    String toHash = lex + "|" + lang + "|" + datatype+"|"+nodeType.getName() ;
    
    char type;
    switch (term.termType) {
        case GTWTermIRI:
            type    = '<';
            break;
        case GTWTermBlank:
            type    = '_';
            break;
        case GTWTermLiteral:
            type    = '"';
            break;
        case GTWTermVariable:
            type    = '?';
            break;
        default:
            NSLog(@"Unexpected type of term: %@", term);
    }
    NSString* language  = [term respondsToSelector:@selector(language)] ? [term language] : @"";
    NSString* datatype  = [term respondsToSelector:@selector(datatype)] ? [term datatype] : @"";
    if (!language)
        language    = @"";
    if (!datatype)
        datatype    = @"";
    
    [d appendData:[[NSString stringWithFormat:@"%c|%@|%@|%@", type, language, datatype, term.value] dataUsingEncoding:NSUTF8StringEncoding]];
    return d;
    
//    NSString* str   = [SPKNTriplesSerializer nTriplesEncodingOfTerm:term escapingUnicode:NO];
//    NSData* data    = [str dataUsingEncoding:NSUTF8StringEncoding];
//    NSLog(@"raw term: %@", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]);
//    NSLog(@"ttl term: %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
//    return data;
    
}

- (id<GTWTerm>) gtw_term {
    char type;
    [self getBytes:&type length:1];
    NSString* string    = [[NSString alloc] initWithData:self encoding:NSUTF8StringEncoding];
    NSMutableArray* parts  = [[string componentsSeparatedByString:@"|"] mutableCopy];
    if ([parts count] > 4) {
        NSArray* lexParts   = [parts subarrayWithRange:NSMakeRange(3, [parts count]-3)];
        NSString* lex       = [lexParts componentsJoinedByString:@""];
        parts               = [@[[parts subarrayWithRange:NSMakeRange(0, 3)], lex] mutableCopy];
    }
    if (type == '<') {
        return [[GTWIRI alloc] initWithValue:parts[3]];
    } else if (type == '_') {
        return [[GTWBlank alloc] initWithValue:parts[3]];
    } else if (type == '"') {
        NSString* parts1    = parts[1];
        NSString* parts2    = parts[2];
        if ([parts1 length]) {
            return [[GTWLiteral alloc] initWithValue:parts[3] language:parts[1]];
        } else if ([parts2 length]) {
            return [[GTWLiteral alloc] initWithValue:parts[3] datatype:parts[2]];
        } else {
            return [[GTWLiteral alloc] initWithValue:parts[3]];
        }
    } else if (type == '?') {
        return [[GTWVariable alloc] initWithValue:parts[3]];
    } else {
        NSLog(@"Unexpected term type: %c", type);
        return nil;
    }
    
    
//    NSString* string        = [[NSString alloc] initWithData:self encoding:NSUTF8StringEncoding];
//    SPKSPARQLLexer* lexer   = [[SPKSPARQLLexer alloc] initWithString:string];
//    // The parser needs the lexer for cases where a term is more than one token (e.g. datatyped literals)
//    SPKTurtleParser* parser = [[SPKTurtleParser alloc] init];
//    parser.lexer = lexer;
//    //    NSLog(@"constructing term from data: %@", data);
//    SPKSPARQLToken* t       = [lexer getTokenWithError:nil];
//    if (!t)
//        return nil;
//    
//    id<GTWTerm> term        = [parser tokenAsTerm:t withErrors:nil];
//    if (!term) {
//        NSLog(@"Cannot create term from token %@", t);
//        return nil;
//    }
//    return term;
}

@end
