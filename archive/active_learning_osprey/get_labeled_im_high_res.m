function [pred, necr, binary_truth, tumor_im, notum_im, calc_width, calc_height, tot_width, tot_height] = get_labeled_im_high_res(weight_file, mark_file, pred_file, tot_width, tot_height)

clusterPointsDisPos = 0.002;
clusterPointsDisNeg = 0.002;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
[w] = textread(weight_file, '%f', 'bufsize', 65536);
lym_w = 1-w(1);
nec_w = w(2);
smh_w = 0.01 + 2 * w(3) * w(3);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
[~, ~, m_type, m_width, tses, poly] = textread(mark_file, '%s%s%s%d%s%s', 'delimiter', '\t', 'bufsize', 65536);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
pred_data = load(pred_file);
pred_data = high_res_pred(pred_data);
x = pred_data(:, 1);
y = pred_data(:, 2);
l = pred_data(:, 3);
if size(pred_data, 2) > 3
    n = pred_data(:, 4);
else
    n = zeros(length(x), 1);
end
calc_width = max(x(:)) + min(x(:));
calc_height = max(y(:)) + min(y(:));
step = (double(min(x(:))) + double(max(x(:)))) / length(unique(x(:)));
fprintf('debug %f %f %f %f\n', min(x(:)), max(x(:)), length(unique(x(:))), step);

x = round((x+step/2) / step);
y = round((y+step/2) / step);

iml = zeros(max(x(:)), max(y(:)));
for iter = 1:length(x)
    iml(x(iter), y(iter)) = l(iter);
end
pred = iml;

imn = zeros(max(x(:)), max(y(:)));
for iter = 1:length(x)
    imn(x(iter), y(iter)) = n(iter);
end
necr = imn;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
k = zeros(3, 3);
for i = 1:3
    for j = 1:3
        k(i, j) = 1.0 / (abs(i-2) + abs(j-2) + smh_w);
    end
end
k = k / sum(k(:));
iml = conv2(iml, k, 'same');

binary_truth = uint8((iml >= lym_w) & (imn < nec_w));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
tumor_countor = {};
tumor_lab = {};
time_stamp = '0';
cur_c = [];
all_tum = [];
all_not = [];
cur_lab = 0;
for iter = 1:length(m_type)
    mt = m_type{iter};
    mw = m_width(iter);
    ts = tses{iter};
    po = str2num(poly{iter});

    if (strcmp(mt, 'LymPos'))
        lab = 1;
        for jter = 1:2:length(po)
            norm_x = po(jter);
            norm_y = po(jter+1);
            binary_truth = marking(binary_truth, lab, mw, norm_x, norm_y, calc_width, calc_height, tot_width, tot_height);
        end
    elseif (strcmp(mt, 'LymNeg'))
        lab = 0;
        for jter = 1:2:length(po)
            norm_x = po(jter);
            norm_y = po(jter+1);
            binary_truth = marking(binary_truth, lab, mw, norm_x, norm_y, calc_width, calc_height, tot_width, tot_height);
        end
    elseif (strcmp(mt, 'TumorPos'))
        if isempty(cur_c) || ...
           (cur_lab == 1 && ...
            abs(str2num(time_stamp) - str2num(ts)) < 50 && ...
            (...
            ((cur_c(end-1)-po(1))^2 + (cur_c(end)-po(2))^2)^0.5 < 0.005 || ...
            ((cur_c(1)-cur_c(end-1))^2 + (cur_c(2)-cur_c(end))^2)^0.5 > 0.005 ...
            )...
           )
            cur_c = [cur_c, po];
        else
            tumor_countor{end+1} = cur_c;
            tumor_lab{end+1} = cur_lab;
            cur_c = po;
        end
        all_tum = [all_tum, po];
        cur_lab = 1;
        time_stamp = ts;
    elseif (strcmp(mt, 'TumorNeg'))
        if isempty(cur_c) || ...
           (cur_lab == 0 && ...
            abs(str2num(time_stamp) - str2num(ts)) < 50 && ...
            (...
            ((cur_c(end-1)-po(1))^2 + (cur_c(end)-po(2))^2)^0.5 < 0.005 || ...
            ((cur_c(1)-cur_c(end-1))^2 + (cur_c(2)-cur_c(end))^2)^0.5 > 0.005 ...
            )...
           )
            cur_c = [cur_c, po];
        else
            tumor_countor{end+1} = cur_c;
            tumor_lab{end+1} = cur_lab;
            cur_c = po;
        end
        all_not = [all_not, po];
        cur_lab = 0;
        time_stamp = ts;
    end
end
if ~isempty(cur_c)
    tumor_countor{end+1} = cur_c;
    tumor_lab{end+1} = cur_lab;
end

all_tum_mat = [all_tum(1:2:end)', all_tum(2:2:end)'];
tum_clusters = clusterPoints(all_tum_mat, clusterPointsDisPos);

if ~isempty(all_not)
    all_not_mat = [all_not(1:2:end)', all_not(2:2:end)'];
    not_clusters = clusterPoints(all_not_mat, clusterPointsDisNeg);
else
    not_clusters = [];
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%tumor_im = zeros(size(iml,1), size(iml,2), 'uint8');
%for i = 1:length(tumor_countor)
%    tumor_im = tumor_poly_to_mask(tumor_im, tumor_countor{i}, tumor_lab{i});
%end

tumor_im = zeros(size(iml,1), size(iml,2), 'uint8');
notum_im = zeros(size(iml,1), size(iml,2), 'uint8');
for i = 1:length(tum_clusters)
    outline = transpose(tum_clusters{i});
    outline = outline(:);
    tumor_im = tumor_poly_to_mask(tumor_im, outline, 1);
end
for i = 1:length(not_clusters)
    outline = transpose(not_clusters{i});
    outline = outline(:);
    notum_im = tumor_poly_to_mask(notum_im, outline, 1);
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [x, y] = defuck(x, y);
if length(x) < 50
    return;
end
x1 = x(5); y1 = y(5); x2 = x(7); y2 = y(7);
dup = 1;
i = 20;
while i < length(x)-6
    if ((abs(x(i)-x1) < 1e-4) && (abs(x(i+4)-x2) < 1e-4) && (abs(y(i)-y1) < 1e-4) && (abs(y(i+4)-y2) < 1e-4))
        dup = dup + 1;
        i = i + 40;
    end
    i = i + 1;
end
if dup > 1
    fprintf('dedup %d\n', dup);
    cut_len = round(length(x)/dup);
    x = x(1:cut_len);
    y = y(1:cut_len);
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function im = tumor_poly_to_mask(im, countor, lab)
% poly_x, poly_y are inverted for poly2mask
poly_x = countor(1:2:end);
poly_y = countor(2:2:end);
%[poly_x, poly_y] = defuck(poly_x, poly_y);

fprintf('Tumor poly length %d [%d]\n', length(poly_x), lab);

if length(poly_x) > 1500
    poly_x = poly_x(1:round(length(poly_x)/500):end);
    poly_y = poly_y(1:round(length(poly_y)/500):end);
end

[poly_x, poly_y] = points2contour(poly_x, poly_y, 1, 'cw');
bw = poly2mask(size(im,2)*poly_y, size(im,1)*poly_x, size(im,1), size(im,2));
if lab == 1
    im = uint8((im +  uint8(bw > 0.5)) > 0.5);
else
    im = uint8((im .* uint8(bw < 0.5)) > 0.5);
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function im = marking(im, lab, width, norm_x, norm_y, calc_width, calc_height, tot_width, tot_height)
norm_step_x = 1.0 / size(im, 1) / 2.0;
norm_step_y = 1.0 / size(im, 2) / 2.0;
if width == 1
    im = marking_one_step(im, lab, norm_x, norm_y, calc_width, calc_height, tot_width, tot_height);
else
    for bi = -3:3
        for bj = -3:3
            norm_x_add = norm_x + bi * norm_step_x;
            norm_y_add = norm_y + bj * norm_step_y;
            im = marking_one_step(im, lab, norm_x_add, norm_y_add, calc_width, calc_height, tot_width, tot_height);
        end
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function im = marking_one_step(im, lab, norm_x, norm_y, calc_width, calc_height, tot_width, tot_height)
im(ceil(size(im,1)*(norm_x*tot_width)/calc_width), ceil(size(im,2)*(norm_y*tot_height)/calc_height)) = lab;


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function hr_pd = high_res_pred(pd)
x = double(pd(:, 1));
step = (double(min(x(:))) + double(max(x(:)))) / length(unique(x(:)));
step = step/4;

hr_pd = zeros(size(pd, 1)*16, size(pd, 2));
for i = 1:size(pd, 1)
    for j = 1:16
        hr_pd((i-1)*16+j, :) = pd(i, :);
        hr_pd((i-1)*16+j, 1:2) = hr_pd((i-1)*16+j, 1:2) - 2*step - step/2;
        ipos = rem(j-1,4)+1;
        jpos = ceil((j-0.001)/4);
        hr_pd((i-1)*16+j, 1) = ceil(hr_pd((i-1)*16+j, 1) + step*ipos);
        hr_pd((i-1)*16+j, 2) = ceil(hr_pd((i-1)*16+j, 2) + step*jpos);
    end
end

