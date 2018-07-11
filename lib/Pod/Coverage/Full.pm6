use v6;
use Pod::Tester;
use Pod::Coverage::Result;
use Pod::Coverage::PodEgg;

unit class Pod::Coverage::Full does Pod::Tester;

#| Sometimes filename is totally out of scope. That's the reason
#| why I left C<$.toload> and C<$.packageStr> separate
has $.toload;
#| Path is for results only
has $.path;
#| P<$.toload>
has $.packageStr;


#| Normally if method is an accessor Pod::Coverage checks
#| field documentation (autogenerated accessors have no pod)
#| anyway they are often self documenting so checking it is
#|  disabled as default
has Bool $.ignore-accessors is rw = True;
#|Attribute list for skipping accessor methods
has @!currentAttr;


method check{
    require ::($!toload);
    my $packageO = ::($!packageStr);

    #start from self        
    self.parse($packageO);
    self.correct-pod($!path) if @.results;
    
    unless @.results {
        my $r = new-result(packagename => $!packageStr, path => $!path);
        $r.is_ok = True;
        @.results.push: $r;
    }
}

#| goes through metaobject tree and searches for .WHY
#| we don't know in what files symbols are in so not setting them to result
method parse($whoO) {
    if ($whoO.WHAT ~~ Routine) {
        # Because Routine is a class it must be checked before generic rule for class
        unless $whoO.WHY {
            if $whoO.WHAT ~~ Method {
                
                for @!currentAttr -> $attr {
                    if $attr.name.subst(/.\!/, "") ~~ $whoO.name {
                        
                        if $attr.has_accessor {
                            return if $!ignore-accessors;
                            unless $attr.WHY {
                                @.results.push: routine-result($attr);
                            }
                            return
                        }
                    }
                }
            }            
            @.results.push: routine-result($whoO);
        }  
    }    
    elsif ($whoO.HOW ~~ Metamodel::PackageHOW) {
        for $whoO.WHO.values -> $clazz {
            self.parse($clazz); 
        }
    }
    elsif ($whoO.HOW ~~ Metamodel::ModuleHOW) {
        for $whoO.WHO.values -> $clazz {
            if $clazz.^name eq 'EXPORT' {
                self.parse-exports($whoO);
            } else {
                self.parse($clazz);
            }
            
        }
    } elsif ($whoO.HOW ~~ Metamodel::ClassHOW ) 
    {
        unless $whoO.WHY {
            @.results.push: new-result(packagename => $whoO.^name);
        }
        
        @!currentAttr = $whoO.^attributes;
        
        for $whoO.^methods(:local) -> $m {                
            self.parse($m);
        }
        
        self.parse-exports($whoO);
        
    }
    elsif ($whoO.HOW ~~ Metamodel::ParametricRoleGroupHOW) {
        for $whoO.^candidates -> $role {                
            self.parse($role);
        }
    }
    elsif ($whoO.HOW ~~ Metamodel::ParametricRoleHOW) {
                        
            self.parse($whoO);
        
    }
    elsif ($whoO ~~ Any::Grepper)
    {
    # it looks like we dont need grepper
    }
    else {
        warn "What is " ~ $whoO.^name ~ " ?";
    }
}

#| Takes whole pod and corrects list made by C<method parse>
#| needs better C<Pod:To::Keywords>
method correct-pod($filename) {
    my $egg = Pod::Coverage::PodEgg.new(orig => $filename);
    my @keywords;
    for $egg.list -> $x { 
        note "Reading $x";
        @keywords.append(read_pod($x));
        note "Done";
    }
    
    return unless @keywords; 
    
    #dd @keywords;

    my @new_results;
    for @.results -> $result {
        
        my $name = $result.name // $result.packagename;

        if $result.what ~~ Sub {  
           @new_results.push: $result unless @keywords.first(/[sub|routine|subroutine]\s+$name/);    #            
     } elsif $result.what ~~ Routine {
        @new_results.push: $result unless @keywords.first(/[method|routine]\s+$name/); 
       } else {
           @new_results.push: $result unless @keywords.first(/\s*$name/); 
       }
    }
    @.results =  @new_results;
}

sub read_pod($filename){
    say "$*EXECUTABLE-NAME --doc=Keywords $filename";
    dd qqx/$*EXECUTABLE-NAME --doc=Keywords $filename/;
    return qqx/$*EXECUTABLE-NAME --doc=Keywords $filename/.lines;
}

sub routine-result($what){
    new-result(packagename => $what.package.^name, name => $what.name);
}

method parse-exports($whoO) {
    for $whoO.WHO<EXPORT>.WHO<ALL>.WHO.values -> $val {
        next unless $val ~~ Sub;
        self.parse($val);
    }
}
