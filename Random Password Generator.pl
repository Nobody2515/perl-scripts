 #!/usr/bin/perl
    @myarray=(A,B,C,1,2,3,4,5,6,7);
    for($i=0;$i<$#myarray;$i++)
    {
    $j=rand(10);
    $randomnum.=$myarray[$j];
    }
    print $randomnum;
