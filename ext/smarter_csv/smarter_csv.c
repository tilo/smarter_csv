#include "ruby.h"
#include "ruby/encoding.h"
#include <stdio.h>
#include <stdbool.h>

#ifndef bool
  #define bool int
  #define false ((bool)0)
  #define true  ((bool)1)
#endif

VALUE SmarterCSV = Qnil;
VALUE eMalformedCSVError = Qnil;
VALUE Parser = Qnil;

static VALUE rb_parse_csv_line(VALUE self, VALUE line, VALUE col_sep, VALUE quote_char, VALUE max_size) {
  if (RB_TYPE_P(line, T_NIL) == 1) {
    return rb_ary_new();
  }

  if (RB_TYPE_P(line, T_STRING) != 1) {
    rb_raise(rb_eTypeError, "ERROR in SmarterCSV.parse_line: line has to be a string or nil");
  }

  rb_encoding *encoding = rb_enc_get(line); /* get the encoding from the input line */
  char *startP = RSTRING_PTR(line); /* may not be null terminated */
  long line_len = RSTRING_LEN(line);
  char *endP = startP + line_len; /* points behind the string */
  char *p = startP;

  char *col_sepP = RSTRING_PTR(col_sep);
  long col_sep_len = RSTRING_LEN(col_sep);

  char *quoteP = RSTRING_PTR(quote_char);
  long quote_count = 0;

  bool col_sep_found = true;

  VALUE elements = rb_ary_new();
  VALUE field;
  long i;

  /* Variables for escaped quote handling */
  long backslash_count = 0;
  bool in_quotes = false;

  while (p < endP) {
    /* does the remaining string start with col_sep ? */
    col_sep_found = true;
    for(i=0; (i < col_sep_len) && (p+i < endP); i++) {
      col_sep_found = col_sep_found && (*(p+i) == *(col_sepP+i));
    }
    /* if col_sep was found and we're not inside quotes */
    if (col_sep_found && !in_quotes) {
      /* if max_size != nil && elements.size >= header_size */
      if ((max_size != Qnil) && RARRAY_LEN(elements) >= NUM2INT(max_size)) {
        break;
      } else {
        /* push that field with original encoding onto the results */
        field = rb_enc_str_new(startP, p - startP, encoding);
        rb_ary_push(elements, field);

        p += col_sep_len;
        startP = p;
        backslash_count = 0; // Reset backslash count at the start of a new field
      }
    } else {
      if (*p == '\\') {
        backslash_count++;
      } else {
        if (*p == *quoteP) {
          if (backslash_count % 2 == 0) {
            /* Even number of backslashes means quote is not escaped */
            in_quotes = !in_quotes;
          }
          /* Else, quote is escaped; do nothing */
        }
        backslash_count = 0; // Reset after any character other than backslash
      }
      p++;
    }
  } /* while */

  /* Check for unclosed quotes at the end of the line */
  if (in_quotes) {
    rb_raise(eMalformedCSVError, "Unclosed quoted field detected in line: %s", StringValueCStr(line));
  }

  /* check if the last part of the line needs to be processed */
  if ((max_size == Qnil) || RARRAY_LEN(elements) < NUM2INT(max_size)) {
    /* copy the remaining line as a field with original encoding onto the results */
    field = rb_enc_str_new(startP, endP - startP, encoding);
    rb_ary_push(elements, field);
  }

  return elements;
}

void Init_smarter_csv(void) {
  // these modules and the error class are already defined in Ruby code, make them accessible:
  SmarterCSV = rb_const_get(rb_cObject, rb_intern("SmarterCSV"));
  Parser = rb_const_get(SmarterCSV, rb_intern("Parser"));
  eMalformedCSVError = rb_const_get(SmarterCSV, rb_intern("MalformedCSV"));

  rb_define_module_function(Parser, "parse_csv_line_c", rb_parse_csv_line, 4);
}
